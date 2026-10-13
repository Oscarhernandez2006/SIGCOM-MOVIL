<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Laravel\Sanctum\HasApiTokens;

// Tabla compartida con el sistema SIGCOM existente (TypeORM); no se crea ni migra desde Laravel.
#[Hidden(['password_hash', 'password_changed_by'])]
class User extends Authenticatable
{
    use HasApiTokens;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $rememberTokenName = '';

    public function getAuthPasswordName(): string
    {
        return 'password_hash';
    }

    public function companies(): HasMany
    {
        return $this->hasMany(UserCompany::class);
    }

    protected function casts(): array
    {
        return [
            'active' => 'boolean',
            'permissions' => 'array',
            'must_change_password' => 'boolean',
            'client_budget' => 'boolean',
            'suite_blocked' => 'boolean',
            'password_changed_at' => 'datetime',
        ];
    }
}
