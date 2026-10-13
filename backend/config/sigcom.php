<?php

// Catálogo de compañías seleccionables; user_companies solo guarda el código.
return [
    // unit: cómo se cuentan las cantidades vendidas (Carnes Frías vende por unidades).
    'companies' => [
        '3' => ['name' => 'AGROPECUARIA', 'logo' => 'santacruz', 'unit' => 'kg'],
        '8' => ['name' => 'CARNES FRIAS', 'logo' => 'carnesfrias', 'unit' => 'und'],
        'MTAT' => ['name' => 'MONTERIA TAT AGROPECUARIA', 'logo' => 'santacruz', 'unit' => 'kg'],
    ],

    // Compañías cuyas ventas facturadas se leen del ERP (mismas consultas que el tablero web).
    'erp_sales_companies' => ['3', '8'],

    // Compañías virtuales que comparten catálogo de clientes con otra compañía real.
    'erp_base_company' => ['MTAT' => '3'],

    // Los subproductos solo se venden en Agropecuaria (la web valida el permiso contra esta compañía).
    'subproduct_company' => '3',

    // Cédulas excluidas del tablero comercial (Juan Sierra, INVERSIONES SERRANO MILLAN).
    'dashboard_excluded_seller_docs' => ['72004911', '900391505'],

    // Vendedor de "Negocios Nacionales" (Juan Sierra): su tablero se ve aparte.
    'national_business_seller_doc' => '72004911',

    'erp' => [
        'base_url' => env('PRICE_LISTS_BASE_URL', 'https://apiconsulta.grupo-santacruz.com'),
        'token' => env('PRICE_LISTS_TOKEN', ''),
        'timeout' => (int) env('PRICE_LISTS_TIMEOUT_MS', 30000) / 1000,
        'cache_seconds' => 300,
    ],

    // API del SIGCOM web (NestJS): crear/anular pedidos pasa por ahí para usar sus mismas reglas y la subida a Siesa.
    'web_api' => [
        'base_url' => env('SIGCOM_API_URL', 'https://sigcom.grupo-santacruz.com/api'),
        'timeout' => (int) env('SIGCOM_API_TIMEOUT', 90),
        // El JWT de la web dura 1 día; se guarda un poco menos para no usarlo vencido.
        'session_hours' => 23,
    ],

    // Igual que getMinOrderTotal() de la web (solo informativo; la web lo valida).
    'min_order_total' => ['3' => 150000, '8' => 50000, 'MTAT' => 0],

    // Vendedores a los que la web no exige registrar la ubicación del cliente.
    'seller_info_exempt_docs' => ['21849701'],

    // Compañías que exigen ubicación del cliente antes de pedir.
    'seller_info_companies' => ['3', '8'],

    // Correo desde el que salen las cotizaciones (buzón de la empresa configurado en MAIL_*).
    'quotes_mail' => [
        'from_address' => env('QUOTES_MAIL_FROM', env('MAIL_FROM_ADDRESS')),
        'company_names' => [
            '3' => 'Agropecuaria Santacruz',
            '8' => 'Carnes Frías Santacruz',
            'MTAT' => 'Montería TAT Agropecuaria',
        ],
    ],
];
