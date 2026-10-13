<?php

use App\Http\Controllers\Api\ApprovalController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\AvailabilityController;
use App\Http\Controllers\Api\ClientController;
use App\Http\Controllers\Api\CompanyController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\FeaturedProductController;
use App\Http\Controllers\Api\HealthController;
use App\Http\Controllers\Api\ManagerialController;
use App\Http\Controllers\Api\OrderController;
use App\Http\Controllers\Api\OrderingController;
use App\Http\Controllers\Api\PortfolioController;
use App\Http\Controllers\Api\PriceListController;
use App\Http\Controllers\Api\QuoteController;
use App\Http\Controllers\Api\ReportController;
use App\Http\Controllers\Api\ScheduleController;
use App\Http\Controllers\Api\SubproductControlController;
use App\Http\Controllers\Api\UserAdminController;
use Illuminate\Support\Facades\Route;

Route::get('/health', HealthController::class);

Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:6,1');

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/user', [AuthController::class, 'me']);
    Route::get('/companies', [CompanyController::class, 'index']);
    Route::get('/dashboard', DashboardController::class);
    Route::get('/orders', [OrderController::class, 'index']);
    Route::get('/orders/{id}', [OrderController::class, 'show'])->whereUuid('id');

    Route::post('/web-session', [AuthController::class, 'webSession'])->middleware('throttle:6,1');

    Route::get('/managerial', [ManagerialController::class, 'index']);
    Route::get('/managerial/sellers', [ManagerialController::class, 'sellers']);

    Route::prefix('reports/{report}')->controller(ReportController::class)->group(function () {
        Route::get('/', 'show');
        Route::get('/file', 'file');
        Route::post('/send', 'send')->middleware('throttle:10,1');
    })->where(['report' => '[a-z\-]+']);

    Route::prefix('availability')->controller(AvailabilityController::class)->group(function () {
        Route::get('/', 'index');
        Route::get('/price-lists', 'priceLists');
        Route::get('/pdf', 'pdf');
        Route::post('/send', 'send')->middleware('throttle:10,1');
    });

    Route::prefix('portfolio')->controller(PortfolioController::class)->group(function () {
        Route::get('/', 'index');
        Route::post('/balances', 'balances');
        Route::get('/{nit}', 'show');
        Route::post('/{nit}/send', 'send')->middleware('throttle:10,1');
    });

    Route::prefix('quotes')->controller(QuoteController::class)->group(function () {
        Route::get('/', 'index');
        Route::post('/', 'store')->middleware('throttle:20,1');
        Route::get('/{id}', 'show')->whereUuid('id');
        Route::get('/{id}/pdf', 'pdf')->whereUuid('id');
        Route::post('/{id}/send', 'send')->whereUuid('id')->middleware('throttle:10,1');
    });
    Route::prefix('approvals')->controller(ApprovalController::class)->group(function () {
        Route::get('/', 'index');
        Route::post('/{id}/approve', 'approve')->whereUuid('id');
        Route::post('/{id}/disapprove', 'disapprove')->whereUuid('id');
    });

    Route::prefix('subproduct-control')->controller(SubproductControlController::class)->group(function () {
        Route::get('/', 'index');
        Route::patch('/{id}', 'update')->whereUuid('id');
        Route::post('/{id}/approve', 'approve')->whereUuid('id');
        Route::post('/{id}/reject', 'reject')->whereUuid('id');
    });

    Route::get('/settings/order-schedule', [ScheduleController::class, 'show']);
    Route::patch('/settings/order-schedule', [ScheduleController::class, 'update'])->middleware('throttle:10,1');

    Route::prefix('admin/users')->controller(UserAdminController::class)->middleware('throttle:60,1')->group(function () {
        Route::get('/', 'index');
        Route::post('/', 'store');
        Route::get('/{id}', 'show')->whereUuid('id');
        Route::patch('/{id}', 'update')->whereUuid('id');
        Route::delete('/{id}', 'destroy')->whereUuid('id');
        Route::patch('/{id}/active', 'setActive')->whereUuid('id');
        Route::post('/{id}/companies', 'assignCompany')->whereUuid('id');
        Route::delete('/{id}/companies/{companyId}', 'removeCompany')->whereUuid('id');
        Route::patch('/{id}/companies/{companyId}/permissions', 'companyPermissions')->whereUuid('id');
    });

    Route::prefix('clients')->controller(ClientController::class)->group(function () {
        Route::get('/', 'index');
        Route::get('/sellers', 'sellers');
        Route::post('/sync', 'sync')->middleware('throttle:3,1');
        Route::get('/{id}', 'show')->whereUuid('id');
    });

    Route::prefix('featured-products')->controller(FeaturedProductController::class)->group(function () {
        Route::get('/', 'index');
        Route::get('/catalog', 'catalog');
        Route::post('/', 'store')->middleware('throttle:30,1');
        Route::delete('/{sku}', 'destroy')->where('sku', '[0-9A-Za-z\-\.]{1,50}')->middleware('throttle:30,1');
    });

    Route::prefix('price-lists')->controller(PriceListController::class)->group(function () {
        Route::get('/', 'index');
        Route::post('/sync', 'sync')->middleware('throttle:3,1');
        Route::get('/{code}', 'items')->where('code', '[0-9A-Za-z\-]{1,20}');
        Route::get('/{code}/pdf', 'pdf')->where('code', '[0-9A-Za-z\-]{1,20}');
    });

    Route::prefix('ordering')->controller(OrderingController::class)->group(function () {
        Route::get('/context', 'context');
        Route::get('/clients', 'clients');
        Route::get('/clients/{id}/today', 'clientToday')->whereUuid('id');
        Route::get('/clients/{id}/location', 'location')->whereUuid('id');
        Route::put('/clients/{id}/location', 'saveLocation')->whereUuid('id');
        Route::get('/products', 'products');
        Route::post('/orders', 'store')->middleware('throttle:20,1');
        Route::post('/orders/{id}/cancel', 'cancel')->whereUuid('id');
    });

    Route::post('/logout', [AuthController::class, 'logout']);
});
