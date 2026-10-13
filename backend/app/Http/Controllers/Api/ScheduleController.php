<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\SigcomWebClient;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Configuración › Horario de pedidos: ventana global en la que se pueden crear pedidos
 * (Montería TAT está exenta). Se lee de la base y se guarda a través de la web.
 */
class ScheduleController extends Controller
{
    private const TIMEZONE = 'America/Bogota';

    public const PERMISSION = '/admin/horario-pedidos';

    public function __construct(private readonly SigcomWebClient $web) {}

    public function show(Request $request): JsonResponse
    {
        $this->authorizeAccess($request);

        return response()->json($this->current());
    }

    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'company' => ['required', 'string', 'max:20'],
            'enabled' => ['required', 'boolean'],
            'open' => ['required', 'date_format:H:i'],
            'close' => ['required', 'date_format:H:i'],
        ]);
        $this->authorizeAccess($request);
        abort_unless(
            $request->user()->companies()->where('company_id', $data['company'])->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );
        abort_if($data['enabled'] && $data['close'] <= $data['open'], 422, 'La hora de cierre debe ser posterior a la de apertura.');

        [$openHour, $openMinute] = array_map('intval', explode(':', $data['open']));
        [$closeHour, $closeMinute] = array_map('intval', explode(':', $data['close']));
        $this->web->call($request->user(), $data['company'], 'PATCH', '/admin/order-schedule', [
            'enabled' => (bool) $data['enabled'],
            'openHour' => $openHour,
            'openMinute' => $openMinute,
            'closeHour' => $closeHour,
            'closeMinute' => $closeMinute,
        ]);

        return response()->json($this->current());
    }

    /** Igual que la web: admin o permiso /admin/horario-pedidos global o en alguna compañía activa. */
    public static function canManage(User $user): bool
    {
        if ($user->role === 'admin' || in_array(self::PERMISSION, $user->permissions ?? [], true)) {
            return true;
        }

        return $user->companies()->where('active', true)->get(['permissions'])
            ->contains(fn ($c) => in_array(self::PERMISSION, $c->permissions ?? [], true));
    }

    private function current(): array
    {
        $row = DB::table('order_schedule_setting')->orderBy('created_at')->first();
        $enabled = $row ? (bool) $row->enabled : true;
        $open = sprintf('%02d:%02d', $row->open_hour ?? 7, $row->open_minute ?? 0);
        $close = sprintf('%02d:%02d', $row->close_hour ?? 16, $row->close_minute ?? 30);
        $now = CarbonImmutable::now(self::TIMEZONE)->format('H:i');

        return [
            'enabled' => $enabled,
            'open' => $open,
            'close' => $close,
            'is_open' => ! $enabled || ($now >= $open && $now < $close),
            'updated_at' => $row?->updated_at
                ? CarbonImmutable::parse($row->updated_at)->setTimezone(self::TIMEZONE)->toIso8601String()
                : null,
        ];
    }

    private function authorizeAccess(Request $request): void
    {
        abort_unless(self::canManage($request->user()), 403, 'No tienes permiso para configurar el horario de pedidos.');
    }
}
