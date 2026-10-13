<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Attachment;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Address;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

class ReportMail extends Mailable
{
    use Queueable;

    public function __construct(
        public readonly string $reportTitle,
        public readonly ?string $subtitle,
        public readonly string $companyName,
        public readonly ?string $senderName,
        public readonly ?string $senderEmail,
        public readonly ?string $customMessage,
        private readonly string $file,
        private readonly string $fileName,
        private readonly string $mime,
    ) {
    }

    public function envelope(): Envelope
    {
        return new Envelope(
            from: new Address(config('sigcom.quotes_mail.from_address'), $this->companyName),
            replyTo: $this->senderEmail ? [new Address($this->senderEmail, $this->senderName ?? '')] : [],
            subject: "{$this->reportTitle} - {$this->companyName}",
        );
    }

    public function content(): Content
    {
        return new Content(view: 'mail.report');
    }

    public function attachments(): array
    {
        return [Attachment::fromData(fn () => $this->file, $this->fileName)->withMime($this->mime)];
    }
}
