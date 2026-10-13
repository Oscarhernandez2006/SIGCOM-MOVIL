<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Response;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Cliente de la API del SIGCOM web (NestJS). Las operaciones que escriben
 * pedidos pasan por aquí para reutilizar sus validaciones y la subida a Siesa.
 * El JWT de la web se guarda cifrado en caché, ligado al token Sanctum.
 */
class SigcomWebClient
{
    public const SESSION_REQUIRED = 'web_session_required';

    /** Inicia sesión en la web con las mismas credenciales y guarda el JWT. */
    public function startSession(User $user, string $password): bool
    {
        try {
            $response = $this->http()->post('/auth/login', [
                'username' => trim($user->document_id),
                'password' => $password,
            ]);
        } catch (ConnectionException $e) {
            Log::warning('SIGCOM web no disponible al iniciar sesión', ['error' => $e->getMessage()]);

            return false;
        }

        $jwt = $response->successful() ? $response->json('accessToken') : null;
        if (! is_string($jwt) || $jwt === '') {
            Log::warning('No se pudo iniciar sesión en SIGCOM web', ['status' => $response->status()]);

            return false;
        }

        Cache::put(
            $this->sessionKey($user),
            Crypt::encryptString($jwt),
            now()->addHours(config('sigcom.web_api.session_hours')),
        );

        return true;
    }

    public function hasSession(User $user): bool
    {
        return Cache::has($this->sessionKey($user));
    }

    public function endSession(User $user): void
    {
        Cache::forget($this->sessionKey($user));
    }

    /**
     * Llama a la API web en nombre del usuario. Devuelve el JSON decodificado
     * (null si la respuesta viene vacía) o corta la petición con un error JSON.
     */
    public function call(User $user, string $company, string $method, string $path, array $data = []): mixed
    {
        $response = $this->send($user, $company, $method, $path, $data);

        return $response->body() === '' ? null : $response->json();
    }

    /** Descarga un archivo de la web (p. ej. el PDF de una cotización) y devuelve su contenido. */
    public function download(User $user, string $company, string $path): string
    {
        return $this->send($user, $company, 'GET', $path)->body();
    }

    private function send(User $user, string $company, string $method, string $path, array $data = []): Response
    {
        $encrypted = Cache::get($this->sessionKey($user));
        if (! $encrypted) {
            $this->sessionRequired();
        }

        try {
            $request = $this->http()->withToken(Crypt::decryptString($encrypted))->withHeaders(['X-Company-Id' => $company]);
            $response = $method === 'GET' ? $request->get($path, $data) : $request->send($method, $path, ['json' => $data === [] ? new \stdClass : $data]);
        } catch (ConnectionException $e) {
            Log::error('SIGCOM web no disponible', ['path' => $path, 'error' => $e->getMessage()]);
            $this->fail(503, 'No se pudo conectar con SIGCOM. Revisa tu conexión e intenta de nuevo.');
        }

        if ($response->status() === 401) {
            $this->endSession($user);
            $this->sessionRequired();
        }
        if ($response->failed()) {
            $this->fail($response->status() >= 500 ? 502 : $response->status(), $this->errorMessage($response));
        }

        return $response;
    }

    private function errorMessage(Response $response): string
    {
        $message = $response->json('message');
        if (is_array($message)) {
            $message = implode(', ', $message);
        }

        return is_string($message) && $message !== '' ? $message : 'SIGCOM respondió con un error ('.$response->status().').';
    }

    private function sessionRequired(): never
    {
        // 428 y no 401: la app trata 401 como sesión móvil vencida y cerraría sesión.
        throw new HttpResponseException(response()->json([
            'code' => self::SESSION_REQUIRED,
            'message' => 'Confirma tu contraseña para continuar con la toma de pedidos.',
        ], 428));
    }

    private function fail(int $status, string $message): never
    {
        throw new HttpResponseException(response()->json(['message' => $message], $status));
    }

    private function sessionKey(User $user): string
    {
        return 'sigcom_web_session:'.$user->currentAccessToken()->getKey();
    }

    private function http()
    {
        return Http::baseUrl(rtrim(config('sigcom.web_api.base_url'), '/'))
            ->timeout(config('sigcom.web_api.timeout'))
            ->acceptJson();
    }
}
