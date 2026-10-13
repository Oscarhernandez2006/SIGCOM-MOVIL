<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// URL pública exigida por Google Play.
Route::view('/privacidad', 'privacy');
