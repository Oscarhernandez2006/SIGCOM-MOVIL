<?php

namespace Tests\Unit;

use App\Models\User;
use App\Services\SigcomWebClient;
use Illuminate\Http\Client\Request;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\TestCase;

class SigcomWebClientTest extends TestCase
{
    private function user(int $tokenId = 7): User
    {
        $token = new PersonalAccessToken;
        $token->id = $tokenId;

        return (new User)->forceFill(['id' => 'u-1', 'document_id' => ' 1234 '])->withAccessToken($token);
    }

    public function test_opens_session_and_forwards_token_and_company(): void
    {
        config(['sigcom.web_api.base_url' => 'https://web.test/api']);
        Http::fake([
            'web.test/api/auth/login' => Http::response(['accessToken' => 'jwt-abc', 'user' => []]),
            'web.test/api/orders' => Http::response(['id' => 'o1', 'orderNumber' => '10', 'status' => 'synced']),
        ]);
        $client = app(SigcomWebClient::class);
        $user = $this->user();

        $this->assertTrue($client->startSession($user, 'secreta'));
        $result = $client->call($user, '3', 'POST', '/orders', ['customerId' => 'c1']);

        $this->assertSame('10', $result['orderNumber']);
        Http::assertSent(fn (Request $r) => $r->url() === 'https://web.test/api/auth/login'
            && $r['username'] === '1234' && $r['password'] === 'secreta');
        Http::assertSent(fn (Request $r) => $r->url() === 'https://web.test/api/orders'
            && $r->hasHeader('Authorization', 'Bearer jwt-abc')
            && $r->hasHeader('X-Company-Id', '3')
            && $r['customerId'] === 'c1');
    }

    public function test_requires_session_when_missing(): void
    {
        Http::fake();
        $response = $this->catchResponse(fn () => app(SigcomWebClient::class)->call($this->user(99), '3', 'GET', '/clients'));

        $this->assertSame(428, $response->getStatusCode());
        $this->assertSame(SigcomWebClient::SESSION_REQUIRED, $response->getData(true)['code']);
        Http::assertNothingSent();
    }

    public function test_expired_web_token_clears_session(): void
    {
        config(['sigcom.web_api.base_url' => 'https://web.test/api']);
        Http::fake([
            'web.test/api/auth/login' => Http::response(['accessToken' => 'jwt-old']),
            'web.test/api/clients*' => Http::response(['message' => 'Unauthorized'], 401),
        ]);
        $client = app(SigcomWebClient::class);
        $user = $this->user(8);
        $client->startSession($user, 'x');

        $response = $this->catchResponse(fn () => $client->call($user, '3', 'GET', '/clients'));

        $this->assertSame(428, $response->getStatusCode());
        $this->assertFalse($client->hasSession($user));
    }

    public function test_business_errors_keep_web_message(): void
    {
        config(['sigcom.web_api.base_url' => 'https://web.test/api']);
        Http::fake([
            'web.test/api/auth/login' => Http::response(['accessToken' => 'jwt']),
            'web.test/api/orders' => Http::response(['statusCode' => 400, 'message' => ['Stock insuficiente', 'SKU inválido']], 400),
        ]);
        $client = app(SigcomWebClient::class);
        $user = $this->user(9);
        $client->startSession($user, 'x');

        $response = $this->catchResponse(fn () => $client->call($user, '3', 'POST', '/orders'));

        $this->assertSame(400, $response->getStatusCode());
        $this->assertSame('Stock insuficiente, SKU inválido', $response->getData(true)['message']);
    }

    public function test_failed_login_does_not_store_session(): void
    {
        config(['sigcom.web_api.base_url' => 'https://web.test/api']);
        Http::fake(['web.test/api/auth/login' => Http::response(['message' => 'Credenciales inválidas'], 401)]);
        $client = app(SigcomWebClient::class);
        $user = $this->user(10);

        $this->assertFalse($client->startSession($user, 'mala'));
        $this->assertFalse($client->hasSession($user));
    }

    private function catchResponse(callable $fn)
    {
        try {
            $fn();
        } catch (HttpResponseException $e) {
            return $e->getResponse();
        }
        $this->fail('Se esperaba una respuesta de error.');
    }
}
