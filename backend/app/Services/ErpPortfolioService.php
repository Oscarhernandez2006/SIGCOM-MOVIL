<?php

namespace App\Services;

use Carbon\CarbonImmutable;
use Illuminate\Http\Client\Pool;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * Cartera (cuentas por cobrar) de un cliente desde el ERP: mismo endpoint que
 * la web (`/cartera?cia&nit`). Se comparte entre sucursales del mismo NIT.
 */
class ErpPortfolioService
{
    private const TIMEZONE = 'America/Bogota';

    private const CACHE_SECONDS = 600;

    private const POOL_SIZE = 10;

    /** @return array{documents: list<array>, summary: array} */
    public function portfolio(string $company, string $nit): array
    {
        $data = Cache::remember($this->key($company, $nit), self::CACHE_SECONDS, function () use ($company, $nit) {
            $response = $this->request(Http::timeout($this->timeout()), $company, $nit);
            if ($response->failed()) {
                Log::error('Error consultando cartera en el ERP', ['nit' => $nit, 'status' => $response->status()]);
                throw new RuntimeException('No se pudo consultar la cartera en Siesa.');
            }

            return $response->json() ?? [];
        });

        return $this->normalize($data);
    }

    /**
     * Resumen de saldo para varios NIT a la vez (consultas en paralelo y en caché).
     *
     * @return array<string, array|null> NIT => resumen, o null si falló.
     */
    public function summaries(string $company, array $nits): array
    {
        $result = [];
        $pending = [];
        foreach ($nits as $nit) {
            $cached = Cache::get($this->key($company, $nit));
            $cached === null ? $pending[] = $nit : $result[$nit] = $this->normalize($cached)['summary'];
        }

        foreach (array_chunk($pending, self::POOL_SIZE) as $chunk) {
            $responses = Http::pool(fn (Pool $pool) => array_map(
                fn ($nit) => $this->request($pool->as($nit)->timeout($this->timeout()), $company, $nit),
                $chunk,
            ));
            foreach ($chunk as $nit) {
                $response = $responses[$nit] ?? null;
                if (! $response instanceof Response || $response->failed()) {
                    $result[$nit] = null;

                    continue;
                }
                $data = $response->json() ?? [];
                Cache::put($this->key($company, $nit), $data, self::CACHE_SECONDS);
                $result[$nit] = $this->normalize($data)['summary'];
            }
        }

        return $result;
    }

    private function normalize(array $data): array
    {
        $today = CarbonImmutable::today(self::TIMEZONE);
        $buckets = ['current' => 0.0, 'd1_30' => 0.0, 'd31_60' => 0.0, 'd61_90' => 0.0, 'd90_plus' => 0.0];
        $total = 0.0;
        $overdue = 0.0;
        $maxDays = 0;
        $documents = [];

        foreach ($data['data'] ?? [] as $row) {
            $balance = (float) ($row['SALDO'] ?? 0);
            $date = $this->date($row['FECHA'] ?? null);
            $due = $this->date($row['FECHA_VCTO'] ?? null);
            $days = $due && $due->lessThan($today) ? (int) $due->diffInDays($today) : 0;

            $total += $balance;
            if ($balance > 0 && $days > 0) {
                $overdue += $balance;
                $maxDays = max($maxDays, $days);
            }
            $bucket = match (true) {
                $days <= 0 => 'current',
                $days <= 30 => 'd1_30',
                $days <= 60 => 'd31_60',
                $days <= 90 => 'd61_90',
                default => 'd90_plus',
            };
            $buckets[$bucket] += $balance;

            $documents[] = [
                'number' => trim((string) ($row['TIPO_DOC_CRUCE'] ?? '')).'-'.($row['CONS_DOC_CRUCE'] ?? ''),
                'type' => trim((string) ($row['DESCRIPCION'] ?? '')),
                'branch' => trim((string) ($row['SUCURSAL'] ?? '')) ?: '001',
                'date' => $date?->toDateString(),
                'due_date' => $due?->toDateString(),
                'days_overdue' => $days,
                'balance' => $balance,
            ];
        }

        usort($documents, fn ($a, $b) => [$b['days_overdue'], $a['due_date']] <=> [$a['days_overdue'], $b['due_date']]);

        $cupo = (float) ($data['cupo'] ?? $data['cupo_credito'] ?? $data['CUPO'] ?? 0);
        if ($cupo <= 0) {
            foreach ($data['data'] ?? [] as $row) {
                $cupo = max($cupo, (float) ($row['CUPO'] ?? $row['CUPO_CREDITO'] ?? $row['VLR_CUPO'] ?? $row['CUPO_APROBADO'] ?? 0));
            }
        }

        return [
            'documents' => $documents,
            'summary' => [
                'total' => round($total, 2),
                'overdue' => round($overdue, 2),
                'current' => round($total - $overdue, 2),
                'max_days_overdue' => $maxDays,
                'documents_count' => count($documents),
                'credit_limit' => $cupo > 0 ? $cupo : null,
                'aging' => array_map(fn ($v) => round($v, 2), $buckets),
                'as_of' => $today->toDateString(),
            ],
        ];
    }

    private function request($http, string $company, string $nit)
    {
        $config = config('sigcom.erp');

        return $http->acceptJson()->get(rtrim($config['base_url'], '/').'/cartera', [
            'cia' => $company,
            'nit' => $nit,
            'token' => $config['token'],
        ]);
    }

    private function date(?string $value): ?CarbonImmutable
    {
        return $value ? CarbonImmutable::parse(substr($value, 0, 10), self::TIMEZONE) : null;
    }

    private function key(string $company, string $nit): string
    {
        return "erp:cartera:{$company}:{$nit}";
    }

    private function timeout(): int
    {
        return (int) config('sigcom.erp.timeout');
    }
}
