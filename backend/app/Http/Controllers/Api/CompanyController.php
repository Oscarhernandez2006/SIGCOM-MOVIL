<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CompanyController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $catalog = config('sigcom.companies');
        $user = $request->user();
        $controlsSubproducts = SubproductControlController::canControl($user);
        $managesSchedule = ScheduleController::canManage($user);

        $companies = $user->companies()
            ->where('active', true)
            ->get(['company_id', 'permissions'])
            ->filter(fn ($access) => isset($catalog[$access->company_id]))
            ->sortBy(fn ($access) => array_search($access->company_id, array_keys($catalog), true))
            ->map(fn ($access) => [
                'id' => $access->company_id,
                ...$catalog[$access->company_id],
                'can_approve' => ApprovalController::canApprove($user, $access->permissions),
                'can_control_subproducts' => $controlsSubproducts
                    && $access->company_id === config('sigcom.subproduct_company'),
                'can_price_lists' => PriceListController::canView($user, $access->permissions),
                'can_featured_products' => FeaturedProductController::canManage($user, $access->permissions),
                'can_clients' => ClientController::canView($user, $access->permissions),
                'can_schedule' => $managesSchedule,
                'can_users' => $user->role === 'admin',
            ])
            ->values();

        return response()->json($companies);
    }
}
