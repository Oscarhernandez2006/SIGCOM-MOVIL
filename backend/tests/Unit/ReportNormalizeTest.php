<?php

namespace Tests\Unit;

use App\Http\Controllers\Api\ReportController;
use App\Mail\ReportMail;
use ReflectionMethod;
use Tests\TestCase;

class ReportNormalizeTest extends TestCase
{
    private function normalize(string $report, array $data): array
    {
        $method = new ReflectionMethod(ReportController::class, 'normalize');

        return $method->invoke(app(ReportController::class), $report, $data);
    }

    public function test_monthly_seller_sales_converts_percentages_and_adds_total(): void
    {
        $row = [
            'name' => 'JOEL PAVA', 'sellerCode' => '012', 'avgKiloPrev' => 10000, 'budgetKilos' => 1000,
            'kilosSold' => 450, 'kilosPct' => 45.0, 'revenue' => 5000000, 'expectedRevenue' => 10000000,
            'revenuePct' => 50.0, 'avgKiloCur' => 11000,
        ];
        $out = $this->normalize('seller-sales', [
            'monthLabel' => 'octubre 2026', 'asOfDate' => '2026-10-11', 'idealPct' => 36.84,
            'rows' => [$row], 'totals' => $row,
        ]);

        $this->assertSame('octubre 2026 · corte 2026-10-11', $out['subtitle']);
        $this->assertEqualsWithDelta(0.3684, $out['kpis'][3]['value'], 1e-9);
        $this->assertSame('JOEL PAVA', $out['rows'][0]['title']);
        $this->assertEqualsWithDelta(0.5, $out['rows'][0]['details'][1]['value'], 1e-9);
        $this->assertSame('TOTAL', $out['total_row']['title']);
        $this->assertTrue($out['total_row']['highlight']);
    }

    public function test_best_seller_by_product_groups_ranking_per_product(): void
    {
        $out = $this->normalize('product-seller', [
            'summary' => ['totalProducts' => 1, 'totalQuantity' => 30, 'totalRevenue' => 900],
            'products' => [['sku' => '1001', 'name' => 'PUNTA DE ANCA']],
            'rows' => [
                ['sku' => '1001', 'productName' => 'PUNTA DE ANCA', 'position' => 2, 'isTop' => false, 'sellerName' => 'B', 'quantity' => 10, 'revenue' => 300],
                ['sku' => '1001', 'productName' => 'PUNTA DE ANCA', 'position' => 1, 'isTop' => true, 'sellerName' => 'A', 'quantity' => 20, 'revenue' => 600],
            ],
        ]);

        $this->assertCount(1, $out['rows']);
        $this->assertSame(900, $out['rows'][0]['value']);
        $this->assertStringContainsString('mejor: A', $out['rows'][0]['subtitle']);
        $this->assertSame('#1 A', $out['rows'][0]['items'][0]['title']);
        $this->assertTrue($out['rows'][0]['items'][0]['highlight']);
    }

    public function test_vendor_product_sales_nests_products_per_seller(): void
    {
        $out = $this->normalize('vendor-product-sales', [
            'periodLabel' => 'Octubre 2026', 'grandTotalQuantity' => 5, 'grandTotalNet' => 100,
            'sellers' => [[
                'nit' => '123', 'name' => 'SANDRA', 'totalQuantity' => 5, 'totalNet' => 100,
                'products' => [['referencia' => '2409', 'descripcion' => 'GRASA', 'quantity' => 5, 'net' => 100]],
            ]],
        ]);

        $this->assertSame(1, $out['kpis'][0]['value']);
        $this->assertSame('GRASA', $out['rows'][0]['items'][0]['title']);
    }

    public function test_report_mail_attaches_excel_with_its_mime(): void
    {
        config(['sigcom.quotes_mail.from_address' => 'reportes@santacruz.com']);
        $mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        $mail = new ReportMail('Ranking de vendedores', '1 oct – 11 oct', 'Agropecuaria Santacruz', 'Admin', null, null, 'xlsx', 'ranking.xlsx', $mime);

        $mail->assertHasSubject('Ranking de vendedores - Agropecuaria Santacruz');
        $mail->assertHasAttachedData('xlsx', 'ranking.xlsx', ['mime' => $mime]);
        $mail->assertSeeInHtml('1 oct – 11 oct');
    }
}
