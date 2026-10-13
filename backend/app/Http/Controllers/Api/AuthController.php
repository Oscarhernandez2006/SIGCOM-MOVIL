<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\SigcomWebClient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function __construct(private readonly SigcomWebClient $web)
    {
    }

    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'document' => ['required', 'string', 'max:50'],
            'password' => ['required', 'string'],
            'device_name' => ['required', 'string', 'max:255'],
        ]);

        $user = User::where('document_id', trim($data['document']))->first();

        // password_verify en vez de Hash::check: los hashes son bcrypt $2b$ generados por Node.
        if (! $user || ! password_verify($data['password'], $user->password_hash) || ! $user->active) {
            throw ValidationException::withMessages([
                'document' => ['Credenciales incorrectas o usuario inactivo.'],
            ]);
        }

        $token = $user->createToken($data['device_name']);
        // Si la web no responde, la app igual entra; pedirá la contraseña al tomar pedidos.
        $this->web->startSession($user->withAccessToken($token->accessToken), $data['password']);

        return response()->json([
            'token' => $token->plainTextToken,
            'user' => $user,
        ]);
    }

    /** Reabre la sesión con la web (su JWT vence a diario) sin cerrar la de la app. */
    public function webSession(Request $request): JsonResponse
    {
        $data = $request->validate(['password' => ['required', 'string']]);
        $user = $request->user();

        if (! password_verify($data['password'], $user->password_hash)) {
            throw ValidationException::withMessages(['password' => ['Contraseña incorrecta.']]);
        }
        abort_unless($this->web->startSession($user, $data['password']), 503, 'No se pudo conectar con SIGCOM. Intenta de nuevo.');

        return response()->json(['message' => 'Sesión confirmada.']);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json($request->user());
    }

    public function logout(Request $request): JsonResponse
    {
        $this->web->endSession($request->user());
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Sesión cerrada.']);
    }
}
