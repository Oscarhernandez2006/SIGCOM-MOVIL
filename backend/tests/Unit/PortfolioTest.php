<?php

namespace Tests\Unit;

use App\Mail\PortfolioMail;
use App\Services\ErpPortfolioService;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class PortfolioTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-10-11 10:00', 'America/Bogota'));
        config(['sigcom.erp.base_url' => 'https://erp.test', 'sigcom.erp.token' => 't']);
    }

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function row(string $due, float $balance, int $n): array
    {
        return ['TIPO_DOC_CRUCE' => '1FE ', 'CONS_DOC_CRUCE' => $n, 'DESCRIPCION' => 'FACTURA', 'SUCURSAL' => '',
            'FECHA' => '2026-08-01T00:00:00', 'FECHA_VCTO' => $due.'T00:00:00', 'SALDO' => $balance];
    }

    public function test_classifies_documents_by_days_overdue(): void
    {
        Http::fake(['erp.test/cartera*' => Http::response(['data' => [
            $this->row('2026-10-20', 100, 1),   // corriente
            $this->row('2026-10-01', 200, 2),   // 10 días
            $this->row('2026-08-27', 300, 3),   // 45 días
            $this->row('2026-07-20', 400, 4),   // 83 días
            $this->row('2026-05-01', 500, 5),   // 163 días
            $this->row('2026-09-01', -50, 6),   // nota crédito vencida: resta del total, no del vencido
        ]])]);

        $result = app(ErpPortfolioService::class)->portfolio('3', '900');
        $s = $result['summary'];

        $this->assertSame(1450.0, $s['total']);
        $this->assertSame(1400.0, $s['overdue']);
        $this->assertSame(163, $s['max_days_overdue']);
        $this->assertSame(['current' => 100.0, 'd1_30' => 200.0, 'd31_60' => 250.0, 'd61_90' => 400.0, 'd90_plus' => 500.0], $s['aging']);
        $this->assertSame('1FE-5', $result['documents'][0]['number']);
        $this->assertSame('001', $result['documents'][0]['branch']);
        Http::assertSent(fn ($r) => $r['cia'] === '3' && $r['nit'] === '900');
    }

    public function test_summaries_marks_failures_without_breaking_the_rest(): void
    {
        Http::fake([
            'erp.test/cartera?cia=3&nit=1*' => Http::response(['data' => [$this->row('2026-10-20', 10, 1)]]),
            'erp.test/cartera?cia=3&nit=2*' => Http::response(['detail' => 'error'], 500),
        ]);

        $result = app(ErpPortfolioService::class)->summaries('3', ['1', '2']);

        $this->assertSame(10.0, $result['1']['total']);
        $this->assertNull($result['2']);
    }

    public function test_mail_shows_server_totals_and_attaches_pdf(): void
    {
        config(['sigcom.quotes_mail.from_address' => 'cartera@santacruz.com']);
        $mail = new PortfolioMail(
            ['nit' => '900', 'name' => 'CLIENTE <i>X</i>'],
            ['total' => 1450, 'overdue' => 1400, 'documents_count' => 6, 'as_of' => '2026-10-11',
                'aging' => ['current' => 100, 'd1_30' => 200, 'd31_60' => 250, 'd61_90' => 400, 'd90_plus' => 500]],
            'Agropecuaria Santacruz', 'JOEL', null, null, '%PDF-1.4',
        );

        $mail->assertHasSubject('Estado de cartera CLIENTE <i>X</i> - Agropecuaria Santacruz');
        $mail->assertSeeInHtml('$ 1.450', false);
        $mail->assertSeeInHtml('11 de octubre de 2026', false);
        $mail->assertDontSeeInHtml('<i>X</i>', false);
        $mail->assertHasAttachedData('%PDF-1.4', 'estado-cartera-900.pdf', ['mime' => 'application/pdf']);
    }
}
