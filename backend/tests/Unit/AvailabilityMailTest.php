<?php

namespace Tests\Unit;

use App\Mail\AvailabilityMail;
use Tests\TestCase;

class AvailabilityMailTest extends TestCase
{
    public function test_builds_mail_with_pdf_and_price_list(): void
    {
        config(['sigcom.quotes_mail.from_address' => 'cotizaciones@santacruz.com']);
        $mail = new AvailabilityMail('Agropecuaria Santacruz', 'GENERAL', 'JOEL PAVA', 'joel@santacruz.com', "Hola\n<script>x</script>", '%PDF-1.4', 'disponibilidad-2026-10-11.pdf');

        $mail->assertFrom('cotizaciones@santacruz.com', 'Agropecuaria Santacruz');
        $mail->assertHasReplyTo('joel@santacruz.com');
        $mail->assertHasSubject('Disponibilidad de productos - Agropecuaria Santacruz');
        $mail->assertHasAttachedData('%PDF-1.4', 'disponibilidad-2026-10-11.pdf', ['mime' => 'application/pdf']);
        $mail->assertSeeInHtml('GENERAL');
        $mail->assertDontSeeInHtml('<script>', false);
    }

    public function test_without_price_list_says_no_prices(): void
    {
        config(['sigcom.quotes_mail.from_address' => 'cotizaciones@santacruz.com']);
        $mail = new AvailabilityMail('Agropecuaria Santacruz', null, null, null, null, '%PDF', 'd.pdf');

        $mail->assertSeeInHtml('(sin precios)');
        $this->assertSame([], $mail->envelope()->replyTo);
    }
}
