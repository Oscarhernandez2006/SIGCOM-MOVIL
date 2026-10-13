<?php

namespace App\Services;

use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * Ventas facturadas del ERP (Siesa) para el tablero comercial; replica las
 * consultas del tablero web: `vendedor-productos-mes` (detalle) y
 * `dashboard-comercial` (totales generales por vendedor).
 */
class ErpSalesService
{
    private const PAGE_SIZE = 5000;

    private const MAX_PAGES = 20;

    /**
     * @param  array<string>  $nits  NIT de los vendedores a incluir; vacío = todos.
     * @param  array{nits: array<string>, names: array<string>}  $exclude
     * @return array{revenue: float, kilos: float, cost: float, by_day: array<string, float>, categories: list<array>}
     */
    public function summary(string $company, array $nits, array $exclude, string $from, string $to): array
    {
        $nitSet = array_flip($nits);
        $excludedNits = array_flip($exclude['nits']);
        $excludedNames = array_flip($exclude['names']);

        $revenue = 0.0;
        $kilos = 0.0;
        $cost = 0.0;
        $byDay = [];
        $categories = [];

        foreach ($this->periods($from, $to) as $period) {
            foreach ($this->productRows($company, $period) as $row) {
                if (! $this->sellerMatches($row, $nitSet, $excludedNits, $excludedNames)) {
                    continue;
                }

                $day = substr((string) ($row['dia'] ?? ''), 0, 10);
                if ($day === '') {
                    continue;
                }

                $ref = trim((string) ($row['referencia_producto'] ?? '')) ?: '—';
                $name = trim((string) ($row['descripcion_producto'] ?? '')) ?: $ref;
                $upperName = mb_strtoupper($name);
                $criterion = mb_strtoupper(trim((string) ($row['categoria'] ?? '')));

                if ($criterion === 'SERVICIO' || str_starts_with($ref, '99') || str_starts_with($upperName, 'SERVICIO')) {
                    continue;
                }

                $isChannel = $criterion === 'CANAL' || str_starts_with($upperName, 'CANAL');
                $category = match (true) {
                    $this->isCarnesFrias($company) => $this->titleCase($criterion) ?: 'Sin categoría',
                    $isChannel => 'Canales',
                    $criterion === 'CORTE' => 'Cortes',
                    $criterion === 'SUBPRODUCTO' => 'Subproductos',
                    default => null,
                };
                if ($category === null) {
                    continue;
                }

                $amount = (float) ($row['total_facturas'] ?? 0);
                // La tendencia usa todos los días del mes, aunque el rango sea menor.
                $byDay[$day] = ($byDay[$day] ?? 0) + $amount;
                if ($day < $from || $day > $to) {
                    continue;
                }

                $qty = (float) ($row['kilos'] ?? 0);
                $revenue += $amount;
                $kilos += $qty;
                $cost += (float) ($row['costo_total'] ?? 0);

                $categories[$category]['kilos'] = ($categories[$category]['kilos'] ?? 0) + $qty;
                $categories[$category]['revenue'] = ($categories[$category]['revenue'] ?? 0) + $amount;
                $item = $categories[$category]['items'][$ref] ?? ['name' => $name, 'ref' => $ref, 'kilos' => 0.0, 'revenue' => 0.0];
                $item['kilos'] += $qty;
                $item['revenue'] += $amount;
                $categories[$category]['items'][$ref] = $item;
            }
        }

        // Los totales oficiales vienen de la consulta general; el detalle queda como respaldo.
        // Carnes Frías no tiene consulta general: su detalle ya es la facturación (en unidades).
        try {
            if (! $this->isCarnesFrias($company)) {
                $general = $this->generalTotals($company, $nitSet, $excludedNits, $excludedNames, $from, $to);
                [$revenue, $kilos, $cost] = [$general['revenue'], $general['kilos'], $general['cost']];
            }
        } catch (RuntimeException) {
        }

        return [
            'revenue' => $revenue,
            'kilos' => $kilos,
            'cost' => $cost,
            'by_day' => $byDay,
            'categories' => $this->formatCategories($categories, ! $this->isCarnesFrias($company)),
        ];
    }

    /**
     * Venta (valor bruto sin IVA) y unidades de Carnes Frías desde `ventas-periodo-inversiones`,
     * como la web: solo para meses completos (desde el día 1 hasta fin de mes u hoy) y si todos
     * los periodos tienen datos; si no, null para usar la facturación diaria.
     *
     * @param  ?string  $sellerName  nombre del vendedor en la app; null = todos menos $excludedNames.
     * @return array{revenue: float, kilos: float}|null
     */
    public function inversionesTotals(string $from, string $to, ?string $sellerName, array $excludedNames): ?array
    {
        $today = CarbonImmutable::today('America/Bogota')->toDateString();
        if (substr($from, 8) !== '01' || ($to !== CarbonImmutable::parse($to)->endOfMonth()->toDateString() && $to < $today)) {
            return null;
        }
        $periods = $this->periods($from, $to);
        try {
            $rows = $this->fetchAll('/ventas/ventas-periodo-inversiones', [
                'cia' => '8',
                'periodo_inicio' => $periods[0],
                'periodo_fin' => end($periods),
            ]);
        } catch (RuntimeException) {
            return null;
        }
        $withData = array_flip(array_map(fn ($r) => (string) ($r['periodo'] ?? ''), $rows));
        foreach ($periods as $period) {
            if (! isset($withData[$period])) {
                return null;
            }
        }

        $revenue = 0.0;
        $units = 0.0;
        foreach ($rows as $row) {
            $name = trim((string) ($row['vendedor'] ?? ''));
            $matches = $sellerName !== null
                ? self::sameSellerName($sellerName, $name)
                : ! collect($excludedNames)->contains(fn ($x) => self::sameSellerName($x, $name));
            if ($matches) {
                $revenue += (float) ($row['vr_bruto'] ?? 0);
                $units += (float) ($row['cantidad'] ?? 0);
            }
        }

        return ['revenue' => $revenue, 'kilos' => $units];
    }

    /** El ERP de Inversiones solo trae "APELLIDOS NOMBRES": se cruza por palabras, igual que la web. */
    public static function sameSellerName(string $appName, string $erpName): bool
    {
        $words = fn (string $n) => array_values(array_filter(preg_split('/\s+/', mb_strtoupper(
            preg_replace('/\p{Mn}/u', '', \Normalizer::normalize($n, \Normalizer::FORM_D))
        ))));
        $app = $words($appName);
        $erp = $words($erpName);

        return $app !== [] && collect($app)->every(fn ($w) => collect($erp)->contains(fn ($e) => self::similarWord($w, $e)));
    }

    /** Iguales, una prefijo de la otra (3+ letras) o con un solo error de digitación. */
    private static function similarWord(string $a, string $b): bool
    {
        if ($a === $b) {
            return true;
        }
        if (str_starts_with($a, $b) || str_starts_with($b, $a)) {
            return min(strlen($a), strlen($b)) >= 3;
        }
        if (abs(strlen($a) - strlen($b)) > 1 || min(strlen($a), strlen($b)) < 4) {
            return false;
        }

        return levenshtein($a, $b) <= 1;
    }

    private function isCarnesFrias(string $company): bool
    {
        return $company === '8';
    }

    private function titleCase(string $value): string
    {
        return mb_convert_case(mb_strtolower(trim($value)), MB_CASE_TITLE);
    }

    /**
     * Venta facturada por cliente (NIT) de un vendedor en el rango; incluye
     * cualquier canal (EDI, cuentas nacionales…), igual que la web.
     *
     * @return array<string, float> NIT cliente => valor
     */
    public function clientSales(string $company, string $sellerNit, string $from, string $to): array
    {
        $rows = $this->fetchAll('/ventas/vendedor-clientes-mes', [
            'id_cia' => $company,
            'fecha_inicio' => $from,
            'fecha_fin' => $to,
        ]);

        $totals = [];
        foreach ($rows as $row) {
            if (trim((string) ($row['CodigoVendedor'] ?? '')) !== $sellerNit) {
                continue;
            }
            $nit = trim((string) ($row['NitCliente'] ?? ''));
            if ($nit !== '') {
                $totals[$nit] = ($totals[$nit] ?? 0) + (float) ($row['ValorSubtotal'] ?? 0);
            }
        }

        return $totals;
    }

    private function generalTotals(string $company, array $nitSet, array $excludedNits, array $excludedNames, string $from, string $to): array
    {
        $totals = ['revenue' => 0.0, 'kilos' => 0.0, 'cost' => 0.0];

        foreach ($this->periods($from, $to) as $period) {
            $monthStart = CarbonImmutable::createFromFormat('!Ym', $period);
            $rows = $this->fetchAll('/ventas/dashboard-comercial', [
                'compania' => $company,
                'periodo' => $period,
                'fecha_inicio' => max($from, $monthStart->toDateString()),
                'fecha_fin' => min($to, $monthStart->endOfMonth()->toDateString()),
            ]);

            foreach ($rows as $row) {
                if (! $this->sellerMatches($row, $nitSet, $excludedNits, $excludedNames)) {
                    continue;
                }
                $totals['revenue'] += (float) ($row['total_facturas'] ?? 0);
                $totals['kilos'] += (float) ($row['kilos'] ?? 0);
                $totals['cost'] += (float) ($row['costo_total'] ?? 0);
            }
        }

        return $totals;
    }

    private function productRows(string $company, string $period): array
    {
        $path = $this->isCarnesFrias($company) ? '/ventas/vendedor-productos-carnesfrias' : '/ventas/vendedor-productos-mes';

        return $this->fetchAll($path, ['compania' => $company, 'periodo' => $period]);
    }

    private function sellerMatches(array $row, array $nitSet, array $excludedNits, array $excludedNames): bool
    {
        $nit = trim((string) ($row['nit_vendedor'] ?? ''));
        if ($nitSet && ! isset($nitSet[$nit])) {
            return false;
        }
        $name = mb_strtoupper(trim((string) ($row['razon_social_vendedor'] ?? '')));

        return ! ($nit !== '' && isset($excludedNits[$nit])) && ! ($name !== '' && isset($excludedNames[$name]));
    }

    private function fetchAll(string $path, array $params): array
    {
        $config = config('sigcom.erp');
        $key = 'erp:'.$path.':'.md5(json_encode($params));

        return Cache::remember($key, $config['cache_seconds'], function () use ($config, $path, $params) {
            $rows = [];
            $offset = 0;
            for ($page = 0; $page < self::MAX_PAGES; $page++) {
                $response = Http::timeout($config['timeout'])
                    ->acceptJson()
                    ->get(rtrim($config['base_url'], '/').$path, $params + [
                        'limit' => self::PAGE_SIZE,
                        'offset' => $offset,
                        'token' => $config['token'],
                    ]);

                if ($response->failed()) {
                    Log::error('Error consultando el ERP', ['path' => $path, 'status' => $response->status()]);
                    throw new RuntimeException('No se pudo consultar las ventas en Siesa.');
                }

                $batch = $response->json('data') ?? [];
                array_push($rows, ...$batch);
                if (! $batch || ! $response->json('has_more')) {
                    break;
                }
                $offset = $response->json('next_offset') ?? $offset + count($batch);
            }

            return $rows;
        });
    }

    /** @return list<string> Periodos YYYYMM que cubre el rango. */
    private function periods(string $from, string $to): array
    {
        $cursor = CarbonImmutable::parse($from)->startOfMonth();
        $end = CarbonImmutable::parse($to)->startOfMonth();
        $periods = [];
        while ($cursor <= $end && count($periods) < 36) {
            $periods[] = $cursor->format('Ym');
            $cursor = $cursor->addMonth();
        }

        return $periods;
    }

    private function formatCategories(array $categories, bool $withMeatGroups = true): array
    {
        foreach ($withMeatGroups ? ['Canales', 'Cortes', 'Subproductos'] : [] as $name) {
            $categories[$name] ??= ['kilos' => 0.0, 'revenue' => 0.0, 'items' => []];
        }

        $result = [];
        foreach ($categories as $name => $category) {
            $items = array_values($category['items'] ?? []);
            usort($items, fn ($a, $b) => $b['revenue'] <=> $a['revenue']);
            $result[] = [
                'category' => $name,
                'kilos' => $category['kilos'],
                'revenue' => $category['revenue'],
                'items' => $items,
            ];
        }
        usort($result, fn ($a, $b) => $b['revenue'] <=> $a['revenue']);

        return $result;
    }
}
