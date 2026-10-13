<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Mail\PortfolioMail;
use App\Services\ErpPortfolioService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use RuntimeException;
use Throwable;

/**
 * Cartera de clientes: los clientes salen de client_records (cartera asignada
 * al vendedor) y los saldos/documentos del ERP, igual que en la web.
 */
class PortfolioController extends Controller
{
    private const LIST_LIMIT = 1000;

    private const BALANCES_BATCH = 30;

    public function __construct(private readonly ErpPortfolioService $erp)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'search' => ['nullable', 'string', 'max:100'],
        ]);
        $company = $data['company'];
        $this->authorizeCompany($request, $company);

        $clients = $this->clientsQuery($request, $company)
            ->when($data['search'] ?? null, function ($q, string $search) {
                $like = '%'.mb_strtolower(trim($search)).'%';
                $q->where(fn ($w) => $w->whereRaw('lower(c.name) like ?', [$like])->orWhere('c.code', 'like', $like));
            })
            ->groupBy('c.code')
            ->orderByRaw('min(c.name)')
            ->limit(self::LIST_LIMIT)
            ->selectRaw('c.code, min(c.name) as name, count(*) as branches, min(c.phone) as phone, min(c.email) as email, min(c.city) as city')
            ->get();

        return response()->json([
            'clients' => $clients->map(fn ($c) => [
                'nit' => $c->code,
                'name' => $c->name,
                'branches' => (int) $c->branches,
                'phone' => $c->phone,
                'email' => $c->email,
                'city' => $c->city,
            ]),
            'limited' => $clients->count() >= self::LIST_LIMIT,
        ]);
    }

    /** Saldos del ERP para un lote de clientes; la app los pide por partes mientras muestra la lista. */
    public function balances(Request $request): JsonResponse
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'nits' => ['required', 'array', 'min:1', 'max:'.self::BALANCES_BATCH],
            'nits.*' => ['required', 'string', 'max:20'],
        ]);
        $this->authorizeCompany($request, $data['company']);

        $allowed = $this->clientsQuery($request, $data['company'])
            ->whereIn('c.code', $data['nits'])
            ->distinct()
            ->pluck('c.code')
            ->all();

        return response()->json($this->erp->summaries($this->baseCompany($data['company']), $allowed));
    }

    public function show(Request $request, string $nit): JsonResponse
    {
        $company = (string) $request->query('company', '');
        $branches = $this->authorizeClient($request, $company, $nit);

        try {
            $portfolio = $this->erp->portfolio($this->baseCompany($company), $nit);
        } catch (RuntimeException $e) {
            abort(502, $e->getMessage());
        }

        return response()->json([
            'client' => $this->clientInfo($nit, $branches),
            'summary' => $portfolio['summary'],
            'documents' => $portfolio['documents'],
        ]);
    }

    public function send(Request $request, string $nit): JsonResponse
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'to' => ['required', 'array', 'min:1', 'max:5'],
            'to.*' => ['required', 'email:rfc', 'max:150'],
            'cc' => ['nullable', 'array', 'max:5'],
            'cc.*' => ['email:rfc', 'max:150'],
            'message' => ['nullable', 'string', 'max:2000'],
            'pdf' => ['required', 'file', 'mimes:pdf', 'max:5120'],
        ]);
        $branches = $this->authorizeClient($request, $data['company'], $nit);

        $pdf = $request->file('pdf')->get();
        abort_unless(str_starts_with($pdf, '%PDF-'), 422, 'El adjunto no es un PDF válido.');

        try {
            $portfolio = $this->erp->portfolio($this->baseCompany($data['company']), $nit);
        } catch (RuntimeException $e) {
            abort(502, $e->getMessage());
        }

        $user = $request->user();
        $client = $this->clientInfo($nit, $branches);
        $companyName = config('sigcom.quotes_mail.company_names')[$data['company']] ?? config('app.name');
        $sellerEmail = filter_var($user->email, FILTER_VALIDATE_EMAIL) ? $user->email : null;

        try {
            Mail::to($data['to'])->cc($data['cc'] ?? [])->send(new PortfolioMail(
                $client,
                $portfolio['summary'],
                $companyName,
                $user->name,
                $sellerEmail,
                trim((string) ($data['message'] ?? '')) ?: null,
                $pdf,
            ));
        } catch (Throwable $e) {
            Log::error('No se pudo enviar el estado de cartera', ['nit' => $nit, 'error' => $e->getMessage()]);
            abort(502, 'No se pudo enviar el correo. Intenta de nuevo más tarde.');
        }

        Log::info('Estado de cartera enviado por correo', [
            'nit' => $nit, 'company' => $data['company'], 'user' => $user->id, 'to' => $data['to'],
        ]);

        return response()->json(['message' => 'Estado de cartera enviado a '.implode(', ', $data['to']).'.']);
    }

    private function clientInfo(string $nit, $branches): array
    {
        $first = $branches->first();

        return [
            'nit' => $nit,
            'name' => $first->name,
            'payment_term' => $first->payment_term,
            'price_list' => $first->price_list,
            'emails' => $branches->pluck('email')->filter()->map(fn ($e) => trim($e))->unique()->values(),
            'phones' => $branches->pluck('phone')->filter()->map(fn ($p) => trim($p))->unique()->values(),
            'branches' => $branches->map(fn ($b) => [
                'code' => $b->branch,
                'name' => $b->branch_name,
                'address' => $b->address,
                'city' => $b->city,
            ])->values(),
        ];
    }

    /** Sucursales del cliente visibles para el usuario; 403/404 si no le corresponde. */
    private function authorizeClient(Request $request, string $company, string $nit)
    {
        $this->authorizeCompany($request, $company);
        abort_unless(preg_match('/^[0-9A-Za-z\-]{3,20}$/', $nit), 404, 'Cliente no encontrado.');

        $branches = $this->clientsQuery($request, $company)
            ->where('c.code', $nit)
            ->orderBy('c.branch')
            ->get(['c.name', 'c.branch', 'c.branch_name', 'c.address', 'c.city', 'c.phone', 'c.email', 'c.payment_term', 'c.price_list']);
        abort_if($branches->isEmpty(), 404, 'Cliente no encontrado en tu cartera.');

        return $branches;
    }

    /** Clientes de la compañía; el vendedor solo ve los asignados a su código Siesa (igual que la web). */
    private function clientsQuery(Request $request, string $company)
    {
        $user = $request->user();
        $query = DB::table('client_records as c')->where('c.company_id', $this->baseCompany($company));

        if ($user->role === 'seller') {
            $code = DB::table('user_companies')
                ->where('user_id', $user->id)
                ->where('company_id', $company)
                ->where('active', true)
                ->value('siesa_seller_code');
            $code = trim((string) ($code ?: $user->siesa_seller_code));
            $query->where('c.seller_code', $code !== '' ? $code : '__sin_codigo__');
        }

        return $query;
    }

    private function baseCompany(string $company): string
    {
        return config('sigcom.erp_base_company')[$company] ?? $company;
    }

    private function authorizeCompany(Request $request, string $company): void
    {
        abort_unless(
            $company !== '' && $request->user()->companies()->where('company_id', $company)->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );
    }
}
