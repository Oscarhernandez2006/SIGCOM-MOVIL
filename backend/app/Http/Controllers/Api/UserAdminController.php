<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\SigcomWebClient;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Configuración › Usuarios (solo administradores, como /admin/usuarios de la web).
 * Lectura directa de users/user_companies; toda escritura pasa por la web (hash, validaciones).
 */
class UserAdminController extends Controller
{
    private const TIMEZONE = 'America/Bogota';

    private const ROLES = ['seller', 'admin', 'cartera', 'alistador', 'facturacion'];

    public function __construct(private readonly SigcomWebClient $web) {}

    public function index(Request $request): JsonResponse
    {
        $this->company($request);

        return response()->json([
            'users' => $this->users()->values(),
            'companies' => collect(config('sigcom.companies'))->map(fn ($c, $id) => ['id' => (string) $id, 'name' => $c['name']])->values(),
        ]);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $this->company($request);

        return response()->json($this->user($id));
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'document_id' => ['required', 'string', 'min:4', 'max:20', 'regex:/^[0-9A-Za-z\-]+$/'],
            'name' => ['required', 'string', 'min:2', 'max:120'],
            'password' => ['required', 'string', 'min:4', 'max:100'],
            'email' => ['nullable', 'email:rfc', 'max:150'],
            'role' => ['required', Rule::in(self::ROLES)],
            'client_budget' => ['nullable', 'boolean'],
        ]);
        $company = $this->company($request);

        $created = $this->web->call($request->user(), $company, 'POST', '/admin/users', array_filter([
            'documentId' => trim($data['document_id']),
            'name' => trim($data['name']),
            'password' => $data['password'],
            'email' => $data['email'] ?? null,
            'role' => $data['role'],
            'clientBudget' => $data['role'] === 'seller' ? (bool) ($data['client_budget'] ?? false) : null,
        ], fn ($v) => $v !== null && $v !== ''));

        return response()->json($this->user((string) ($created['id'] ?? '')), 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $data = $request->validate([
            'document_id' => ['sometimes', 'string', 'min:4', 'max:20', 'regex:/^[0-9A-Za-z\-]+$/'],
            'name' => ['sometimes', 'string', 'min:2', 'max:120'],
            'email' => ['sometimes', 'nullable', 'email:rfc', 'max:150'],
            'role' => ['sometimes', Rule::in(self::ROLES)],
            'client_budget' => ['sometimes', 'boolean'],
            'password' => ['sometimes', 'nullable', 'string', 'min:4', 'max:100'],
        ]);
        $company = $this->company($request);
        $this->user($id);
        abort_if(
            $id === $request->user()->id && isset($data['role']) && $data['role'] !== 'admin',
            422,
            'No puedes quitarte el rol de administrador.'
        );

        $body = array_filter([
            'documentId' => isset($data['document_id']) ? trim($data['document_id']) : null,
            'name' => isset($data['name']) ? trim($data['name']) : null,
            'role' => $data['role'] ?? null,
            'clientBudget' => $data['client_budget'] ?? null,
            'password' => ($data['password'] ?? '') !== '' ? $data['password'] : null,
        ], fn ($v) => $v !== null);
        if (array_key_exists('email', $data)) {
            $body['email'] = $data['email'] ?: null;
        }
        $this->web->call($request->user(), $company, 'PATCH', "/admin/users/{$id}", $body);

        return response()->json($this->user($id));
    }

    public function setActive(Request $request, string $id): JsonResponse
    {
        $data = $request->validate(['active' => ['required', 'boolean']]);
        $company = $this->company($request);
        abort_if($id === $request->user()->id, 422, 'No puedes desactivar tu propio usuario.');
        $this->user($id);
        $this->web->call($request->user(), $company, 'PATCH', "/admin/users/{$id}/active", ['active' => (bool) $data['active']]);

        return response()->json($this->user($id));
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $company = $this->company($request);
        abort_if($id === $request->user()->id, 422, 'No puedes eliminar tu propio usuario.');
        $this->user($id);
        $this->web->call($request->user(), $company, 'DELETE', "/admin/users/{$id}");

        return response()->json(['message' => 'Usuario eliminado.']);
    }

    /** Asigna la compañía (o actualiza su código de vendedor Siesa). */
    public function assignCompany(Request $request, string $id): JsonResponse
    {
        $data = $request->validate([
            'company_id' => ['required', Rule::in(array_keys(config('sigcom.companies')))],
            'siesa_seller_code' => ['nullable', 'string', 'max:20'],
        ]);
        $company = $this->company($request);
        $this->user($id);
        $this->web->call($request->user(), $company, 'POST', "/admin/users/{$id}/companies", array_filter([
            'companyId' => $data['company_id'],
            'siesaSellerCode' => trim((string) ($data['siesa_seller_code'] ?? '')),
        ], fn ($v) => $v !== ''));

        return response()->json($this->user($id));
    }

    public function removeCompany(Request $request, string $id, string $companyId): JsonResponse
    {
        $company = $this->company($request);
        $this->user($id);
        abort_if(
            $id === $request->user()->id && $companyId === $company,
            422,
            'No puedes quitarte la compañía en la que estás trabajando.'
        );
        $this->web->call($request->user(), $company, 'DELETE', "/admin/users/{$id}/companies/".rawurlencode($companyId));

        return response()->json($this->user($id));
    }

    public function companyPermissions(Request $request, string $id, string $companyId): JsonResponse
    {
        $data = $request->validate([
            'permissions' => ['present', 'array', 'max:60'],
            'permissions.*' => ['string', 'max:80', 'regex:/^\/[a-z0-9\-\/]*$/'],
        ]);
        $company = $this->company($request);
        $this->user($id);
        $this->web->call(
            $request->user(),
            $company,
            'PATCH',
            "/admin/users/{$id}/companies/".rawurlencode($companyId).'/permissions',
            ['permissions' => array_values(array_unique($data['permissions']))],
        );

        return response()->json($this->user($id));
    }

    private function user(string $id): array
    {
        $user = $this->users(fn ($q) => $q->where('u.id', $id))->first();
        abort_unless($user, 404, 'Usuario no encontrado.');

        return $user;
    }

    private function users(?callable $scope = null)
    {
        $catalog = config('sigcom.companies');
        $query = DB::table('users as u')->orderBy('u.name');
        if ($scope) {
            $scope($query);
        }
        $users = $query->get([
            'u.id', 'u.document_id', 'u.email', 'u.name', 'u.role', 'u.active', 'u.client_budget',
            'u.siesa_seller_code', 'u.must_change_password', 'u.password_changed_at', 'u.created_at',
        ]);
        $companies = DB::table('user_companies')
            ->whereIn('user_id', $users->pluck('id'))
            ->where('active', true)
            ->get(['user_id', 'company_id', 'siesa_seller_code', 'permissions'])
            ->groupBy('user_id');

        return $users->map(fn ($u) => [
            'id' => $u->id,
            'document_id' => $u->document_id,
            'email' => $u->email,
            'name' => $u->name,
            'role' => $u->role,
            'active' => (bool) $u->active,
            'client_budget' => (bool) $u->client_budget,
            'must_change_password' => (bool) $u->must_change_password,
            'password_changed_at' => $this->iso($u->password_changed_at),
            'created_at' => $this->iso($u->created_at),
            'companies' => ($companies[$u->id] ?? collect())
                ->filter(fn ($c) => isset($catalog[$c->company_id]))
                ->sortBy(fn ($c) => array_search($c->company_id, array_keys($catalog), true))
                ->map(fn ($c) => [
                    'id' => $c->company_id,
                    'name' => $catalog[$c->company_id]['name'] ?? $c->company_id,
                    'siesa_seller_code' => $c->siesa_seller_code ?: $u->siesa_seller_code,
                    'permissions' => is_string($c->permissions)
                        ? (json_decode($c->permissions, true) ?? [])
                        : ($c->permissions ?? []),
                ])->values(),
        ]);
    }

    /** Solo administradores (en la web todos los endpoints de usuarios son AdminOnly). */
    private function company(Request $request): string
    {
        abort_unless($request->user()->role === 'admin', 403, 'Solo un administrador puede gestionar usuarios.');
        $company = (string) $request->input('company', $request->query('company', ''));
        abort_unless(
            $company !== '' && $request->user()->companies()->where('company_id', $company)->where('active', true)->exists(),
            403,
            'No tienes acceso a esta compañía.'
        );

        return $company;
    }

    private function iso(?string $value): ?string
    {
        return $value ? CarbonImmutable::parse($value)->setTimezone(self::TIMEZONE)->toIso8601String() : null;
    }
}
