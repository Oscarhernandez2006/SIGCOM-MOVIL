<?php

namespace Tests\Unit;

use App\Http\Controllers\Api\ApprovalController;
use App\Http\Controllers\Api\SubproductControlController;
use App\Models\User;
use App\Services\SigcomWebClient;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\TestCase;

class ApprovalTest extends TestCase
{
    public function test_who_can_approve(): void
    {
        $user = fn (string $role) => (new User)->forceFill(['role' => $role]);

        $this->assertTrue(ApprovalController::canApprove($user('admin'), null));
        $this->assertTrue(ApprovalController::canApprove($user('cartera'), []));
        $this->assertTrue(ApprovalController::canApprove($user('seller'), ['/admin/pedidos', '/admin/cartera']));
        $this->assertFalse(ApprovalController::canApprove($user('seller'), ['/admin/pedidos']));
        $this->assertFalse(ApprovalController::canApprove($user('alistador'), null));
    }

    public function test_admin_or_global_permission_controls_subproducts(): void
    {
        $this->assertTrue(SubproductControlController::canControl((new User)->forceFill(['role' => 'admin'])));
        $this->assertTrue(SubproductControlController::canControl(
            (new User)->forceFill(['role' => 'alistador', 'permissions' => ['/admin/controlador-subproductos']])
        ));
    }

    public function test_empty_body_is_sent_as_json_object(): void
    {
        config(['sigcom.web_api.base_url' => 'https://web.test/api']);
        Http::fake([
            'web.test/api/auth/login' => Http::response(['accessToken' => 'jwt']),
            'web.test/api/cartera/orders/*' => Http::response(['id' => 'o1', 'status' => 'synced']),
        ]);
        $token = new PersonalAccessToken;
        $token->id = 3;
        $user = (new User)->forceFill(['id' => 'u-1', 'document_id' => '1'])->withAccessToken($token);
        $client = app(SigcomWebClient::class);
        $client->startSession($user, 'x');

        $client->call($user, '3', 'POST', '/cartera/orders/o1/approve');

        Http::assertSent(fn (Request $r) => str_ends_with($r->url(), '/approve') && $r->body() === '{}');
    }
}
