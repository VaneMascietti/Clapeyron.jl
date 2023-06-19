struct AsymmetricMixingParam <: EoSParam
    gamma_T::PairParam{Float64}
    gamma_v::PairParam{Float64}
    beta_T::PairParam{Float64}
    beta_v::PairParam{Float64}
end

@newmodelsimple AsymmetricMixing MixingRule AsymmetricMixingParam


"""
    QuadraticDeparture <: MultiFluidDepartureModel
    QuadraticDeparture(components; 
    userlocations=String[],
    verbose=false)

## Input parameters
- `beta_v`: Pair Parameter (`Float64`) - binary interaction parameter  (no units)
- `gamma_v`: Pair Parameter (`Float64`) - binary interaction parameter  (no units)
- `beta_T`: Pair Parameter (`Float64`) - binary interaction parameter  (no units)
- `gamma_T`: Pair Parameter (`Float64`) - binary interaction parameter  (no units)

## Description
Asymmetric mixing rule for MultiParameter EoS models:

```
τ = T̄/T
δ = V̄/V
V̄ = ∑xᵢxⱼ * βᵛᵢⱼ * γᵛᵢⱼ * (xᵢ + xⱼ)/(xᵢ*βᵛᵢⱼ^2 + xⱼ) * Vᵣᵢⱼ
T̄ = ∑xᵢxⱼ * βᵛᵢⱼ * γᵀᵢⱼ * (xᵢ + xⱼ)/(xᵢ*βᵀᵢⱼ^2 + xⱼ) * Tᵣᵢⱼ
Vᵣᵢⱼ = 0.125*(∛Vcᵢ + ∛Vcⱼ)^3
Tᵣᵢⱼ = √(Tcᵢ*Tcⱼ)
```

With the asymmetry present in the β parameters:
```
βᵛᵢⱼ = 1/βᵛⱼᵢ
βᵀᵢⱼ = 1/βᵀⱼᵢ
```

If there is no data present, the parameters can be estimated:
```
βᵛᵢⱼ = βᵛᵢⱼ = 1
γᵛᵢⱼ = 4*(Vcᵢ + Vcⱼ)/(∛Vcᵢ + ∛Vcⱼ)^3
γᵀᵢⱼ = 0.5*(Tcᵢ + Tcⱼ)/√(Tcᵢ*Tcⱼ)
```
"""
function AsymmetricMixing(components;userlocations = String[],verbose = false)
    params = getparams(components,["Empiric/mixing/AsymmetricMixing/asymmetric_mixing_unlike.csv"]; asymmetricparams = ["beta_v","beta_T"],userlocations=userlocations, verbose=verbose)
    beta_v = params["beta_v"]
    gamma_v = params["gamma_v"]
    beta_T = params["beta_T"]
    gamma_T = params["gamma_T"]
    mirror_pair!(beta_T,inv)
    mirror_pair!(beta_v,inv)
    pkgparams = AsymmetricMixingParam(gamma_T,gamma_v,beta_T,beta_v)
    return AsymmetricMixing(pkgparams,verbose = verbose)
end

function recombine_mixing!(model::MultiFluid,mixing::AsymmetricMixing)
    Vc = model.params.Vc.values
    Tc = model.params.Tc.values
    n = length(model)
    γT = mixing.params.gamma_T
    γv = mixing.params.gamma_v
    βT = mixing.params.beta_T
    βv = mixing.params.beta_v
    for i in 1:n
        for j in 1:n
            if γT.ismissingvalues[i,j]
                γT[i,j] = 0.5*(Tc[i]+Tc[j])/sqrt(Tc[i]*Tc[j])
            end
            if γv.ismissingvalues[i,j]
                γv[i,j] = 0.25*(Vc[i]+Vc[j])/(cbrt(Vc[i])+cbrt(Vc[j])^3)
            end
            if βT.ismissingvalues[i,j]
                βT[i,j] = 1.0
            end
            if βv.ismissingvalues[i,j]
                βv[i,j] = 1.0
            end
        end
    end
end

function v_scale(model::MultiFluid,z,mixing::AsymmetricMixing,∑z)
    vc = model.params.Vc.values
    res = mixing_rule_asymmetric(
        mix_mean3,
        _gerg_asymmetric_mix_rule,
        z,
        vc,
        mixing.params.gamma_v.values,
        mixing.params.beta_v.values,
    )
    return res/(∑z*∑z)
end

function T_scale(model::MultiFluid,z,mixing::AsymmetricMixing,∑z)
    Tc = model.params.Tc.values
    #isone(length(z)) && return only(Tc)
    return mixing_rule_asymmetric(
        mix_geomean,
        _gerg_asymmetric_mix_rule,
        z,
        Tc,
        mixing.params.gamma_T.values,
        mixing.params.beta_T.values,
    )/(∑z*∑z)
end

"""
    mixing_rule_asymmetric(op, op_asym, x, p, A, A_asym)

returns an efficient implementation of:
` sum(A[i,j] * x[i] * x[j] * op(p[i],p[j]) * op_asym(x[i],x[j],A_asym[i,j])) for i = 1:n , j = 1:n)`
where `op(p[i],p[j]) == op(p[j],p[i])` , op_asym doesn't follow this symmetry.

""" 
function mixing_rule_asymmetric(op, op_asym, x, p, A, A_asym)
    N = length(x)
    checkbounds(A, N, N)
    checkbounds(A_asym, N, N)
    @boundscheck checkbounds(p, N)
    @inbounds begin
        res1 = zero(eltype(x))
        for i = 1:N
            xi = x[i]
            xi != 0 && begin
                p_i = p[i]
                res1 += p_i * xi^2
                for j = 1:i - 1
                    res1 += 2*xi*x[j]*op(p_i, p[j])*A[i, j]*op_asym(xi, x[j], A_asym[i, j])
                end
            end
        end
    end
    
    return res1
end

_gerg_asymmetric_mix_rule(xi, xj, b) = b * (xi + xj) / (xi * b^2 + xj)

export AsymmetricMixing