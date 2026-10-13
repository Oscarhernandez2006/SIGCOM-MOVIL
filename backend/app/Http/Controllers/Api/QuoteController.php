<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Mail\QuoteMail;
use App\Services\SigcomWebClient;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Cotizaciones: la consulta se lee de la base; crear y generar el PDF pasa por
 * la web (precios de la lista del cliente, consecutivo e impuestos). El envío
 * por correo es propio de la app y adjunta ese mismo PDF.
 */
class QuoteController extends Controller
{
    private const TIMEZONE = 'America/Bogota';

    public function __construct(private readonly SigcomWebClient $web)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'search' => ['nullable', 'string', 'max:100'],
        ]);
        $this->authorizeCompany($request, $data['company']);

        $quotes = $this->baseQuery($request, $data['company'])
            ->when($data['search'] ?? null, function ($q, string $search) {
                $like = '%'.mb_strtolower(trim($search)).'%';
                $q->where(fn ($w) => $w
                    ->whereRaw('lower(c.name) like ?', [$like])
                    ->orWhere('c.code', 'like', $like)
                    ->orWhere('q.quote_number', 'like', $like));
            })
            ->orderByDesc('q.created_at')
            ->limit(200)
            ->get()
            ->map(fn ($q) => $this->summary($q));

        return response()->json($quotes);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $quote = $this->findQuote($request, $id);
        $items = DB::table('quote_items')
            ->where('quote_id', $id)
            ->orderBy('product_name')
            ->get(['sku', 'product_name', 'unit_of_measure', 'quantity', 'unit_price', 'discount_pct', 'tax_rate', 'line_total'])
            ->map(fn ($i) => [
                'sku' => $i->sku,
                'name' => $i->product_name,
                'unit' => $i->unit_of_measure,
                'quantity' => (float) $i->quantity,
                'unit_price' => (float) $i->unit_price,
                'discount_pct' => (float) $i->discount_pct,
                'tax_rate' => (float) $i->tax_rate,
                'total' => (float) $i->line_total,
            ]);

        return response()->json($this->summary($quote) + [
            'subtotal' => (float) $quote->subtotal,
            'taxes' => (float) $quote->taxes,
            'notes' => $quote->notes,
            'validity_days' => (int) $quote->validity_days,
            'items' => $items,
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'customer_id' => ['required', 'uuid'],
            'notes' => ['nullable', 'string', 'max:1000'],
            'validity_days' => ['required', 'integer', 'between:1,365'],
            'items' => ['required', 'array', 'min:1'],
            'items.*.sku' => ['required', 'string', 'max:50'],
            'items.*.quantity' => ['required', 'integer', 'min:1'],
            'items.*.discount_pct' => ['nullable', 'numeric', 'between:0,100'],
        ]);
        $this->authorizeCompany($request, $data['company']);

        $quote = $this->web->call($request->user(), $data['company'], 'POST', '/quotes', array_filter([
            'customerId' => $data['customer_id'],
            'notes' => trim((string) ($data['notes'] ?? '')) ?: null,
            'validityDays' => (int) $data['validity_days'],
            'items' => array_map(fn ($i) => [
                'sku' => $i['sku'],
                'quantity' => (int) $i['quantity'],
                'discountPct' => (float) ($i['discount_pct'] ?? 0),
            ], $data['items']),
        ], fn ($v) => $v !== null));

        return response()->json([
            'id' => $quote['id'] ?? null,
            'number' => $quote['quoteNumber'] ?? null,
            'total' => (float) ($quote['total'] ?? 0),
        ], 201);
    }

    public function pdf(Request $request, string $id): Response
    {
        $quote = $this->findQuote($request, $id);
        $pdf = $this->web->download($request->user(), $quote->company_id, "/quotes/{$id}/pdf");

        return response($pdf, 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'attachment; filename="cotizacion-'.$quote->quote_number.'.pdf"',
        ]);
    }

    public function send(Request $request, string $id): JsonResponse
    {
        $data = $request->validate([
            'to' => ['required', 'array', 'min:1', 'max:5'],
            'to.*' => ['required', 'email:rfc', 'max:150'],
            'cc' => ['nullable', 'array', 'max:5'],
            'cc.*' => ['email:rfc', 'max:150'],
            'message' => ['nullable', 'string', 'max:2000'],
        ]);
        $quote = $this->findQuote($request, $id);
        $user = $request->user();

        $pdf = $this->web->download($user, $quote->company_id, "/quotes/{$id}/pdf");
        $companyName = config('sigcom.quotes_mail.company_names')[$quote->company_id] ?? config('app.name');
        $summary = $this->summary($quote);
        $sellerEmail = filter_var($user->email, FILTER_VALIDATE_EMAIL) ? $user->email : null;

        try {
            Mail::to($data['to'])
                ->cc($data['cc'] ?? [])
                ->send(new QuoteMail($summary, $companyName, $user->name, $sellerEmail, trim((string) ($data['message'] ?? '')) ?: null, $pdf));
        } catch (Throwable $e) {
            Log::error('No se pudo enviar la cotización por correo', ['quote' => $id, 'error' => $e->getMessage()]);
            abort(502, 'No se pudo enviar el correo. Intenta de nuevo más tarde.');
        }

        Log::info('Cotización enviada por correo', [
            'quote' => $quote->quote_number, 'company' => $quote->company_id, 'user' => $user->id, 'to' => $data['to'],
        ]);

        return response()->json(['message' => 'Cotización enviada a '.implode(', ', $data['to']).'.']);
    }

    private function baseQuery(Request $request, string $company)
    {
        return DB::table('quotes as q')
            ->join('client_records as c', 'c.id', '=', 'q.customer_id')
            ->leftJoin('users as u', 'u.id', '=', 'q.seller_id')
            ->where('q.company_id', $company)
            ->when($request->user()->role === 'seller', fn ($q) => $q->where('q.seller_id', $request->user()->id))
            ->select([
                'q.*',
                'c.name as customer_name', 'c.code as customer_code', 'c.branch_name', 'c.city',
                'c.email as customer_email', 'c.phone as customer_phone', 'c.price_list',
                'u.name as seller_name',
            ])
            ->selectSub(DB::table('quote_items')->whereColumn('quote_id', 'q.id')->selectRaw('count(*)'), 'items_count');
    }

    /** Busca la cotización respetando compañía y, para vendedores, que sea suya. */
    private function findQuote(Request $request, string $id): object
    {
        $companyId = DB::table('quotes')->where('id', $id)->value('company_id');
        abort_unless($companyId, 404, 'Cotización no encontrada.');
        $this->authorizeCompany($request, $companyId);

        $quote = $this->baseQuery($request, $companyId)->where('q.id', $id)->first();
        abort_unless($quote, 403, 'No tienes acceso a esta cotización.');

        return $quote;
    }

    private function summary(object $q): array
    {
        $validUntil = $q->valid_until ? CarbonImmutable::parse($q->valid_until)->setTimezone(self::TIMEZONE) : null;

        return [
            'id' => $q->id,
            'number' => $q->quote_number,
            'total' => (float) $q->total,
            'items_count' => (int) $q->items_count,
            'created_at' => CarbonImmutable::parse($q->created_at)->setTimezone(self::TIMEZONE)->toIso8601String(),
            'valid_until' => $validUntil?->toIso8601String(),
            'expired' => $validUntil !== null && $validUntil->isPast(),
            'seller' => $q->seller_name,
            'customer_name' => $q->customer_name,
            'customer' => [
                'name' => $q->customer_name,
                'code' => $q->customer_code,
                'branch' => $q->branch_name ?? $q->city,
                'email' => $q->customer_email,
                'phone' => $q->customer_phone,
                'price_list' => $q->price_list,
            ],
        ];
    }

    private function authorizeCompany(Request $request, string $company): void
    {
        abort_unless(
            $request->user()->companies()->where('company_id', $company)->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );
    }
}
