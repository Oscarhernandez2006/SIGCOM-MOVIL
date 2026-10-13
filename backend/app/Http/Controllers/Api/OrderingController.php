<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\SigcomWebClient;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Toma de pedidos: delega en la API del SIGCOM web y solo devuelve campos
 * necesarios (la web expone entidades completas, p. ej. el vendedor anidado).
 */
class OrderingController extends Controller
{
    private const TIMEZONE = 'America/Bogota';

    public function __construct(private readonly SigcomWebClient $web)
    {
    }

    public function context(Request $request): JsonResponse
    {
        $company = $this->company($request);
        $user = $request->user();

        $schedule = $this->web->call($user, $company, 'GET', '/settings/order-schedule') ?? [];
        $featured = $this->web->call($user, $company, 'GET', '/featured-products') ?? [];

        return response()->json([
            'schedule' => $this->schedule($company, $schedule),
            'min_total' => config('sigcom.min_order_total')[$company] ?? 0,
            'requires_location' => in_array($company, config('sigcom.seller_info_companies'), true)
                && ! in_array(trim((string) $user->document_id), config('sigcom.seller_info_exempt_docs'), true),
            'featured' => collect($featured)->map(fn ($f) => ['sku' => $f['sku'], 'name' => $f['name']])->values(),
        ]);
    }

    public function clients(Request $request): JsonResponse
    {
        $company = $this->company($request);
        $search = (string) $request->query('search', '');
        $rows = $this->web->call($request->user(), $company, 'GET', '/clients', array_filter(['search' => trim($search)])) ?? [];

        return response()->json(collect($rows)->map(fn ($c) => [
            'id' => $c['id'],
            'code' => $c['code'],
            'name' => $c['name'],
            'branch' => $c['branch'] ?? null,
            'branch_name' => $c['branchName'] ?? null,
            'price_list' => $c['priceList'] ?? null,
            'price_list_name' => $c['priceListName'] ?? null,
            'payment_term' => $c['paymentTerm'] ?? null,
            'address' => $c['address'] ?? null,
            'city' => $c['city'] ?? null,
            'phone' => $c['phone'] ?? null,
            'email' => $c['email'] ?? null,
            'delivery_schedule' => $c['deliverySchedule'] ?? null,
        ])->values());
    }

    public function products(Request $request): JsonResponse
    {
        $company = $this->company($request);
        $data = $request->validate([
            'price_list' => ['required', 'string', 'max:20'],
            'type' => ['nullable', 'in:corte,subproducto'],
        ]);
        $rows = $this->web->call($request->user(), $company, 'GET', '/products', array_filter([
            'priceList' => $data['price_list'],
            'type' => $data['type'] ?? null,
        ])) ?? [];

        return response()->json(collect($rows)->map(fn ($p) => [
            'sku' => $p['sku'],
            'name' => $p['name'],
            'price' => (float) ($p['price'] ?? 0),
            'unit' => $p['unitOfMeasure'] ?? null,
            'stock' => (float) ($p['stock'] ?? 0),
            'tax_rate' => (float) ($p['taxRate'] ?? 0),
            'category' => $p['category'] ?? null,
        ])->values());
    }

    /** Pedidos de hoy del cliente, para ofrecer asociar el nuevo (igual que la web). */
    public function clientToday(Request $request, string $id): JsonResponse
    {
        $company = $this->company($request);
        $user = $request->user();
        $today = $this->web->call($user, $company, 'GET', '/orders/customer-today', ['customerId' => $id]);
        if (! ($today['hasOrder'] ?? false)) {
            return response()->json(['has_order' => false, 'orders' => []]);
        }

        $orders = $this->web->call($user, $company, 'GET', '/orders/today-by-customer', ['customerId' => $id]) ?? [];

        return response()->json([
            'has_order' => true,
            'orders' => collect($orders)->map(fn ($o) => [
                'id' => $o['id'],
                'number' => $o['orderNumber'],
                'total' => (float) ($o['total'] ?? 0),
                'created_at' => $o['createdAt'] ?? null,
            ])->values(),
        ]);
    }

    public function location(Request $request, string $id): JsonResponse
    {
        $info = $this->web->call($request->user(), $this->company($request), 'GET', "/clients/{$id}/seller-info");

        return response()->json(['location' => $info ? $this->locationFields($info) : null]);
    }

    public function saveLocation(Request $request, string $id): JsonResponse
    {
        $data = $request->validate([
            'direccion' => ['required', 'string', 'max:255'],
            'barrio' => ['required', 'string', 'max:120'],
            'ciudad' => ['required', 'string', 'max:120'],
            'referencia' => ['nullable', 'string', 'max:255'],
            'departamento' => ['nullable', 'string', 'max:120'],
            'telefono' => ['nullable', 'string', 'max:40'],
        ]);
        $info = $this->web->call($request->user(), $this->company($request), 'PUT', "/clients/{$id}/seller-info", array_filter($data));

        return response()->json(['location' => $this->locationFields($info ?? $data)]);
    }

    public function store(Request $request): JsonResponse
    {
        $company = $this->company($request);
        $data = $request->validate([
            'customer_id' => ['required', 'uuid'],
            'delivery_date' => ['required', 'date_format:Y-m-d'],
            'delivery_type' => ['required', 'in:despacho,recoge_en_planta'],
            'notes' => ['nullable', 'string', 'max:500'],
            'logistics_note' => ['nullable', 'string', 'max:500'],
            'delivery_schedule' => ['nullable', 'array'],
            'delivery_schedule.days' => ['required_with:delivery_schedule', 'array', 'min:1'],
            'delivery_schedule.days.*' => ['integer', 'between:0,6'],
            'delivery_schedule.hour_from' => ['required_with:delivery_schedule', 'date_format:H:i'],
            'delivery_schedule.hour_to' => ['required_with:delivery_schedule', 'date_format:H:i'],
            'delivery_schedule_text' => ['nullable', 'string', 'max:255'],
            'items' => ['required', 'array', 'min:1'],
            'items.*.sku' => ['required', 'string', 'max:50'],
            'items.*.quantity' => ['required', 'integer', 'min:1'],
            'idempotency_key' => ['required', 'string', 'max:100'],
            'linked_order_id' => ['nullable', 'uuid'],
        ]);

        $schedule = $data['delivery_schedule'] ?? null;
        $order = $this->web->call($request->user(), $company, 'POST', '/orders', array_filter([
            'customerId' => $data['customer_id'],
            'deliveryDate' => $data['delivery_date'],
            'deliveryType' => $data['delivery_type'],
            'notes' => $data['notes'] ?? null,
            'logisticsNote' => $data['logistics_note'] ?? null,
            'deliverySchedule' => $data['delivery_schedule_text'] ?? null,
            'deliveryScheduleData' => $schedule ? [
                'days' => array_map('intval', $schedule['days']),
                'hourFrom' => $schedule['hour_from'],
                'hourTo' => $schedule['hour_to'],
            ] : null,
            'items' => array_map(fn ($i) => ['sku' => $i['sku'], 'quantity' => (int) $i['quantity'], 'discountPct' => 0], $data['items']),
            'idempotencyKey' => $data['idempotency_key'],
            'linkedOrderId' => $data['linked_order_id'] ?? null,
        ], fn ($v) => $v !== null && $v !== ''));

        return response()->json($this->orderResult($order), 201);
    }

    public function cancel(Request $request, string $id): JsonResponse
    {
        $data = $request->validate(['reason' => ['required', 'string', 'max:500']]);
        $order = $this->web->call($request->user(), $this->company($request), 'POST', "/orders/{$id}/cancel", ['reason' => trim($data['reason'])]);

        return response()->json($this->orderResult($order));
    }

    private function orderResult(?array $order): array
    {
        return [
            'id' => $order['id'] ?? null,
            'number' => $order['orderNumber'] ?? null,
            'second_number' => $order['secondNumber'] ?? null,
            'status' => $order['status'] ?? null,
            'total' => (float) ($order['total'] ?? 0),
            'sync_error' => $order['syncError'] ?? null,
            'approval_deadline' => $order['approvalDeadline'] ?? null,
        ];
    }

    private function locationFields(array $info): array
    {
        return collect($info)->only(['direccion', 'referencia', 'barrio', 'ciudad', 'departamento', 'telefono'])->all();
    }

    /** Horario para crear pedidos en hora Colombia; Montería TAT no tiene restricción. */
    private function schedule(string $company, array $config): array
    {
        $enabled = ($config['enabled'] ?? true) && $company !== 'MTAT';
        $open = sprintf('%02d:%02d', $config['openHour'] ?? 7, $config['openMinute'] ?? 0);
        $close = sprintf('%02d:%02d', $config['closeHour'] ?? 16, $config['closeMinute'] ?? 30);
        $now = CarbonImmutable::now(self::TIMEZONE)->format('H:i');

        return [
            'enabled' => $enabled,
            'open' => $open,
            'close' => $close,
            'is_open' => ! $enabled || ($now >= $open && $now < $close),
        ];
    }

    private function company(Request $request): string
    {
        $company = (string) $request->input('company', $request->query('company', ''));
        abort_unless(
            $company !== '' && $request->user()->companies()->where('company_id', $company)->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );

        return $company;
    }
}
