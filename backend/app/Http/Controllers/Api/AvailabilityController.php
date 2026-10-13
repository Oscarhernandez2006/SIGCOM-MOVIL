<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Mail\AvailabilityMail;
use App\Services\SigcomWebClient;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Disponibilidad: productos con existencias (y precio de una lista opcional)
 * y su PDF, tomados de la web igual que la página /disponibilidad.
 */
class AvailabilityController extends Controller
{
    public function __construct(private readonly SigcomWebClient $web)
    {
    }

    public function index(Request $request): JsonResponse
    {
        [$company, $priceList] = $this->params($request);
        $rows = $this->web->call($request->user(), $company, 'GET', '/products/stock', array_filter(['priceList' => $priceList])) ?? [];

        return response()->json(collect($rows)->map(fn ($p) => [
            'sku' => $p['sku'],
            'name' => $p['name'],
            'unit' => $p['unitOfMeasure'] ?? null,
            'stock' => (float) ($p['stock'] ?? 0),
            'price' => isset($p['price']) ? (float) $p['price'] : null,
            'category' => $p['category'] ?? null,
        ])->values());
    }

    public function priceLists(Request $request): JsonResponse
    {
        [$company] = $this->params($request);
        $rows = $this->web->call($request->user(), $company, 'GET', '/price-lists') ?? [];

        return response()->json(collect($rows)->map(fn ($l) => [
            'code' => $l['listCode'],
            'name' => $l['listName'],
        ])->values());
    }

    public function pdf(Request $request): Response
    {
        [$company, $priceList] = $this->params($request);
        $pdf = $this->web->download($request->user(), $company, $this->pdfPath($priceList));

        return response($pdf, 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'attachment; filename="'.$this->fileName().'"',
        ]);
    }

    public function send(Request $request): JsonResponse
    {
        [$company, $priceList] = $this->params($request);
        $data = $request->validate([
            'price_list_name' => ['nullable', 'string', 'max:120'],
            'to' => ['required', 'array', 'min:1', 'max:5'],
            'to.*' => ['required', 'email:rfc', 'max:150'],
            'cc' => ['nullable', 'array', 'max:5'],
            'cc.*' => ['email:rfc', 'max:150'],
            'message' => ['nullable', 'string', 'max:2000'],
        ]);
        $user = $request->user();
        $pdf = $this->web->download($user, $company, $this->pdfPath($priceList));
        $companyName = config('sigcom.quotes_mail.company_names')[$company] ?? config('app.name');
        $sellerEmail = filter_var($user->email, FILTER_VALIDATE_EMAIL) ? $user->email : null;

        try {
            Mail::to($data['to'])->cc($data['cc'] ?? [])->send(new AvailabilityMail(
                $companyName,
                $priceList ? ($data['price_list_name'] ?? $priceList) : null,
                $user->name,
                $sellerEmail,
                trim((string) ($data['message'] ?? '')) ?: null,
                $pdf,
                $this->fileName(),
            ));
        } catch (Throwable $e) {
            Log::error('No se pudo enviar la disponibilidad por correo', ['error' => $e->getMessage()]);
            abort(502, 'No se pudo enviar el correo. Intenta de nuevo más tarde.');
        }

        Log::info('Disponibilidad enviada por correo', ['company' => $company, 'user' => $user->id, 'to' => $data['to']]);

        return response()->json(['message' => 'Disponibilidad enviada a '.implode(', ', $data['to']).'.']);
    }

    /** @return array{0: string, 1: ?string} compañía autorizada y lista de precios opcional */
    private function params(Request $request): array
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'price_list' => ['nullable', 'string', 'max:20', 'regex:/^[0-9A-Za-z\-]+$/'],
        ]);
        abort_unless(
            $request->user()->companies()->where('company_id', $data['company'])->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );

        return [$data['company'], $data['price_list'] ?? null];
    }

    private function pdfPath(?string $priceList): string
    {
        return '/products/stock/pdf'.($priceList ? '?priceList='.rawurlencode($priceList) : '');
    }

    private function fileName(): string
    {
        return 'disponibilidad-'.CarbonImmutable::now('America/Bogota')->toDateString().'.pdf';
    }
}
