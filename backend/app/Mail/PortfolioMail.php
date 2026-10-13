<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Attachment;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Address;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

class PortfolioMail extends Mailable
{
    use Queueable;

    public function __construct(
        public readonly array $client,
        public readonly array $summary,
        public readonly string $companyName,
        public readonly ?string $sellerName,
        public readonly ?string $sellerEmail,
        public readonly ?string $customMessage,
        private readonly string $pdf,
    ) {
    }

    public function envelope(): Envelope
    {
        return new Envelope(
            from: new Address(config('sigcom.quotes_mail.from_address'), $this->companyName),
            replyTo: $this->sellerEmail ? [new Address($this->sellerEmail, $this->sellerName ?? '')] : [],
            subject: "Estado de cartera {$this->client['name']} - {$this->companyName}",
        );
    }

    public function content(): Content
    {
        return new Content(view: 'mail.portfolio');
    }

    public function attachments(): array
    {
        return [
            Attachment::fromData(fn () => $this->pdf, "estado-cartera-{$this->client['nit']}.pdf")->withMime('application/pdf'),
        ];
    }
}
