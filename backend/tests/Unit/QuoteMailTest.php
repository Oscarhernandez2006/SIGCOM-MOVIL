<?php

namespace Tests\Unit;

use App\Mail\QuoteMail;
use Tests\TestCase;

class QuoteMailTest extends TestCase
{
    private function mail(?string $message = null, ?string $sellerEmail = 'vendedor@santacruz.com'): QuoteMail
    {
        config(['sigcom.quotes_mail.from_address' => 'cotizaciones@santacruz.com']);

        return new QuoteMail(
            ['number' => '000011', 'customer_name' => 'CLIENTE <b>PRUEBA</b>', 'total' => 1234567, 'items_count' => 3, 'valid_until' => '2026-10-26T08:00:00-05:00'],
            'Agropecuaria Santacruz',
            'JOEL PAVA',
            $sellerEmail,
            $message,
            '%PDF-1.4 contenido',
        );
    }

    public function test_builds_envelope_with_company_sender_and_seller_reply_to(): void
    {
        $mail = $this->mail();

        $mail->assertFrom('cotizaciones@santacruz.com', 'Agropecuaria Santacruz');
        $mail->assertHasReplyTo('vendedor@santacruz.com', 'JOEL PAVA');
        $mail->assertHasSubject('Cotización 000011 - Agropecuaria Santacruz');
        $mail->assertHasAttachedData('%PDF-1.4 contenido', 'cotizacion-000011.pdf', ['mime' => 'application/pdf']);
    }

    public function test_renders_summary_and_escapes_user_text(): void
    {
        $mail = $this->mail("Hola,\n<script>alert(1)</script>");

        $mail->assertSeeInHtml('$ 1.234.567', false);
        $mail->assertSeeInHtml('26 de octubre de 2026', false);
        $mail->assertDontSeeInHtml('<script>', false);
        $mail->assertDontSeeInHtml('<b>PRUEBA</b>', false);
    }

    public function test_without_seller_email_has_no_reply_to(): void
    {
        $mail = $this->mail(sellerEmail: null);

        $this->assertSame([], $mail->envelope()->replyTo);
        $mail->assertDontSeeInHtml('llegará al asesor');
    }
}
