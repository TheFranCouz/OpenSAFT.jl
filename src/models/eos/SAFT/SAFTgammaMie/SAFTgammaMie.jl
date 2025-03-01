struct SAFTgammaMieParam <: EoSParam
    segment::SingleParam{Int}
    shapefactor::SingleParam{Float64}
    lambda_a::PairParam{Float64}
    lambda_r::PairParam{Float64}
    sigma::PairParam{Float64}
    epsilon::PairParam{Float64}
    epsilon_assoc::AssocParam{Float64}
    bondvol::AssocParam{Float64}
end

abstract type SAFTgammaMieModel <: GCSAFTModel end
@newmodelgc SAFTgammaMie SAFTgammaMieModel SAFTgammaMieParam

const SAFTγMie = SAFTgammaMie
export SAFTgammaMie,SAFTγMie
function SAFTgammaMie(components::Array{<:Any,1}; idealmodel::Type=BasicIdeal, userlocations::Array{String,1}=String[], verbose=false)
    groups = buildspecies(components, ["SAFT/SAFTgammaMie/SAFTgammaMie_groups.csv"]; verbose=verbose)
    params = getparams(groups, ["SAFT/SAFTgammaMie"]; userlocations=userlocations, verbose=verbose)

    segment = params["vst"]
    shapefactor = params["S"]

    params["sigma"].values .*= 1E-10
    sigma = sigma_LorentzBerthelot(params["sigma"])
    epsilon = epsilon_HudsenMcCoubrey(params["epsilon"], sigma)
    lambda_a = lambda_LorentzBerthelot(params["lambda_a"])
    lambda_r = lambda_LorentzBerthelot(params["lambda_r"])

    epsilon_assoc = params["epsilon_assoc"]
    bondvol = params["bondvol"]

    sites = SiteParam(Dict("e1" => params["n_e1"], "e2" => params["n_e2"], "H" => params["n_H"]))

    packagedparams = SAFTgammaMieParam(segment, shapefactor, lambda_a, lambda_r, sigma, epsilon, epsilon_assoc, bondvol)
    references = ["10.1063/1.4851455", "10.1021/je500248h"]

    model = SAFTgammaMie(packagedparams, groups, sites, idealmodel; references=references, verbose=verbose)
    return model
end

function a_res(model::SAFTgammaMieModel, V, T, z)
    return @f(a_mono) + @f(a_chain) + @f(a_assoc)
end

function a_mono(model::SAFTgammaMieModel, V, T, z)
    return @f(ÂHS) + @f(Â_1) + @f(Â_2) + @f(Â_3)
end

function a_chain(model::SAFTgammaMieModel, V, T, z)
    x = z/∑(z)
    v = model.allcomponentnflattenedgroups
    vst = model.params.segment.values
    S = model.params.shapefactor.values
    return -∑(x[i] * (∑(v[i][k]*vst[k]*S[k] for k ∈ @groups(i))-1) * log(@f(g_Mie,i)) for i ∈ @comps)
end

function a_assoc(model::SAFTgammaMieModel, V, T, z)
    x = z/∑(z)
    v = model.allcomponentnflattenedgroups
    n = model.allgroupnsites
    X_ = @f(X)
    return ∑(x[i] * ∑(v[i][k] * ∑(n[k][a] * (log(X_[i][k][a])+(1-X_[i][k][a])/2) for a ∈ @sites(k)) for k ∈ @groups(i)) for i ∈ @comps)
end

function ÂHS(model::SAFTgammaMieModel, V, T, z)
    ζ_0   = @f(ζ,0)
    ζ_1   = @f(ζ,1)
    ζ_2   = @f(ζ,2)
    ζ_3   = @f(ζ,3)
    ρ = ∑(z)*N_A/V
    return 6/π/ρ * (3ζ_1*ζ_2/(1-ζ_3) + ζ_2^3/(ζ_3*(1-ζ_3)^2) + (ζ_2^3/ζ_3^2-ζ_0)*log(1-ζ_3))
end

function Â_1(model::SAFTgammaMieModel, V, T, z)
    x = z/∑(z)
    v = model.allcomponentnflattenedgroups
    vst = model.params.segment.values
    S = model.params.shapefactor.values
    return 1/T * ∑(x[i]*∑(v[i][k]*vst[k]*S[k] for k ∈ @groups(i)) for i ∈ @comps) * @f(a_1)
end
function Â_2(model::SAFTgammaMieModel, V, T, z)
    x = z/∑(z)
    v = model.allcomponentnflattenedgroups
    vst = model.params.segment.values
    S = model.params.shapefactor.values
    return 1/T^2 * ∑(x[i]*∑(v[i][k]*vst[k]*S[k] for k ∈ @groups(i)) for i ∈ @comps) * @f(a_2)
end
function Â_3(model::SAFTgammaMieModel, V, T, z)
    x = z/∑(z)
    v = model.allcomponentnflattenedgroups
    vst = model.params.segment.values
    S = model.params.shapefactor.values
    return 1/T^3 * ∑(x[i]*∑(v[i][k]*vst[k]*S[k] for k ∈ @groups(i)) for i ∈ @comps) * @f(a_3)
end

function a_1(model::SAFTgammaMieModel, V, T, z)
    return ∑(@f(x_S,k)*@f(x_S,l)*@f(a_1,k,l) for k ∈ @groups for l ∈ @groups)
end
function a_2(model::SAFTgammaMieModel, V, T, z)
    return ∑(@f(x_S,k)*@f(x_S,l)*@f(a_2,k,l) for k ∈ @groups for l ∈ @groups)
end
function a_3(model::SAFTgammaMieModel, V, T, z)
    return ∑(@f(x_S,k)*@f(x_S,l)*@f(a_3,k,l) for k ∈ @groups for l ∈ @groups)
end

function a_1(model::SAFTgammaMieModel, V, T, z, k, l)
    σ = model.params.sigma.values[k,l]
    λa = model.params.lambda_a.values[k,l]
    λr = model.params.lambda_r.values[k,l]

    x_0 = σ/@f(d,k,l)
    return @f(C,λa,λr) * (x_0^λa*(@f(aS_1,k,l,λa)+@f(B,k,l,λa)) - x_0^λr*(@f(aS_1,k,l,λr)+@f(B,k,l,λr)))
end
function a_2(model::SAFTgammaMieModel, V, T, z, k, l)
    σ = model.params.sigma.values[k,l]
    ϵ = model.params.epsilon.values[k,l]
    λa = model.params.lambda_a.values[k,l]
    λr = model.params.lambda_r.values[k,l]

    x_0 = σ/@f(d,k,l)
    return 1/2*@f(KHS)*(1+@f(χ,k,l))*ϵ*@f(C,λa,λr)^2 * (
           x_0^(2λa)*(@f(aS_1,k,l,2λa) + @f(B,k,l,2λa))
         - 2x_0^(λa+λr)*(@f(aS_1,k,l,λa+λr) + @f(B,k,l,λa+λr))
         + x_0^(2λr)*(@f(aS_1,k,l,2λr) + @f(B,k,l,2λr)) )
end
function a_3(model::SAFTgammaMieModel, V, T, z, k, l)
    ϵ = model.params.epsilon.values[k,l]
    ζst_X_ = @f(ζst_X)
    return -ϵ^3*@f(f,k,l,4)*ζst_X_ * exp(@f(f,k,l,5)*ζst_X_ + @f(f,k,l,6)*ζst_X_^2)
end

function B(model::SAFTgammaMieModel, V, T, z, k, l, λ)
    ϵ = model.params.epsilon.values[k,l]
    σ = model.params.sigma.values[k,l]
    x_0 = σ/@f(d,k,l)
    ζ_X_ = @f(ζ_X)
    I = (1-x_0^(3-λ))/(λ-3)
    J = (1-x_0^(4-λ)*(λ-3)+x_0^(3-λ)*(λ-4))/((λ-3)*(λ-4))
    return 2π*@f(ρ_S)*@f(d,k,l)^3*ϵ * ((1-ζ_X_/2)/(1-ζ_X_)^3*I-9ζ_X_*(1+ζ_X_)/(2(1-ζ_X_)^3)*J)
end

function aS_1(model::SAFTgammaMieModel, V, T, z, k, l, λ)
    ϵ = model.params.epsilon.values[k,l]
    ζeff_ = @f(ζeff, λ)
    return -2π*@f(ρ_S) * ϵ*@f(d,k,l)^3/(λ-3) * (1-ζeff_/2)/(1-ζeff_)^3
end

function ζ_X(model::SAFTgammaMieModel, V, T, z)
    return π*@f(ρ_S)/6 * ∑(@f(x_S,k)*@f(x_S,l)*@f(d,k,l)^3 for k ∈ @groups for l ∈ @groups)
end

function ζst_X(model::SAFTgammaMieModel, V, T, z)
    σ = model.params.sigma.values
    return π*@f(ρ_S)/6 * ∑(@f(x_S,k)*@f(x_S,l)*σ[k,l]^3 for k ∈ @groups for l ∈ @groups)
end

function ζeff(model::SAFTgammaMieModel, V, T, z, λ)
    A = SAFTγMieconsts.A
    ζ_X_ = @f(ζ_X)
    return A * [1; 1/λ; 1/λ^2; 1/λ^3] ⋅ [ζ_X_; ζ_X_^2; ζ_X_^3; ζ_X_^4]
end

function KHS(model::SAFTgammaMieModel, V, T, z)
    ζ_X_ = @f(ζ_X)
    return (1-ζ_X_)^4/(1+4ζ_X_+4ζ_X_^2-4ζ_X_^3+ζ_X_^4)
end

function χ(model::SAFTgammaMieModel, V, T, z, k, l)
    ζst_X_ = @f(ζst_X)
    return @f(f,k,l,1)*ζst_X_ + @f(f,k,l,2)*ζst_X_^5 + @f(f,k,l,3)*ζst_X_^8
end

function f(model::SAFTgammaMieModel, V, T, z, k, l, m)
    ϕ = SAFTγMieconsts.ϕ
    λa = model.params.lambda_a.values[k,l]
    λr = model.params.lambda_r.values[k,l]

    α = @f(C,λa,λr)*(1/(λa-3)-1/(λr-3))
    return ∑(ϕ[i+1][m]*α^i for i ∈ 0:3)/(1+∑(ϕ[i+1][m]*α^(i-3) for i ∈ 4:6))
end

function ζ(model::SAFTgammaMieModel, V, T, z, m)
    return π/6*@f(ρ_S)*∑(@f(x_S,k)*@f(d,k)^m for k ∈ @groups)
end

function ρ_S(model::SAFTgammaMieModel, V, T, z)
    x = z/∑(z)
    v = model.allcomponentnflattenedgroups
    vst = model.params.segment.values
    S = model.params.shapefactor.values
    ρ = ∑(z)*N_A/V
    return ρ * ∑(x[i] * ∑(v[i][k]*vst[k]*S[k] for k ∈ @groups(i)) for i ∈ @comps)
end

function x_S(model::SAFTgammaMieModel, V, T, z, k)
    x = z/∑(z)
    v = model.allcomponentnflattenedgroups
    vst = model.params.segment.values
    S = model.params.shapefactor.values
    return ∑(x[i]*v[i][k]*vst[k]*S[k] for i ∈ @comps) / ∑(x[i] * ∑(v[i][l]*vst[l]*S[l] for l ∈ @groups(i)) for i ∈ @comps)
end

function d(model::SAFTgammaMieModel, V, T, z, k)
    ϵ = model.params.epsilon.diagvalues[k]
    σ = model.params.sigma.diagvalues[k]
    λa = model.params.lambda_a.diagvalues[k]
    λr = model.params.lambda_r.diagvalues[k]
    u = SAFTγMieconsts.u
    w = SAFTγMieconsts.w
    θ = @f(C,λa,λr)*ϵ/T
    return σ*(1-∑(w[j]*(θ./(θ+u[j]))^(1/λr)*(exp(θ*(1/(θ./(θ+u[j]))^(λa/λr)-1))/(u[j]+θ)/λr) for j ∈ 1:5))
end

function d(model::SAFTgammaMieModel, V, T, z, k, l)
    # Lorentz mixing rule
    if k == l
        return @f(d, k)
    else
        return (@f(d, k) + @f(d, l))/2
    end
end

function C(model::SAFTgammaMieModel, V, T, z, λa, λr)
    return (λr/(λr-λa)) * (λr/λa)^(λa/(λr-λa))
end

function ẑ(model::SAFTgammaMieModel, V, T, z, i, k)
    v = model.allcomponentnflattenedgroups
    vst = model.params.segment.values
    S = model.params.shapefactor.values
    return v[i][k]*vst[k]*S[k] / ∑(v[i][l]*vst[l]*S[l] for l ∈ @groups(i))
end

function σ̄(model::SAFTgammaMieModel, V, T, z, i)
    σ = model.params.sigma.values
    return cbrt(∑(∑(@f(ẑ,i,k)*@f(ẑ,i,l)*σ[k,l]^3 for l ∈ @groups) for k ∈ @groups))
end

function σ̄(model::SAFTgammaMieModel, V, T, z, i, j)
    if i == j
        return @f(σ̄, i)
    else
        return (@f(σ̄, i) + @f(σ̄, j))/2
    end
end

function d̄(model::SAFTgammaMieModel, V, T, z, i)
    return cbrt(∑(∑(@f(ẑ,i,k)*@f(ẑ,i,l)*@f(d,k,l)^3 for l ∈ @groups) for k ∈ @groups))
end

function ϵ̄(model::SAFTgammaMieModel, V, T, z, i)
    ϵ = model.params.epsilon.values
    return ∑(∑(@f(ẑ,i,k)*@f(ẑ,i,l)*ϵ[k,l] for l ∈ @groups) for k ∈ @groups)
end

function ϵ̄(model::SAFTgammaMieModel, V, T, z, i, j)
    if i == j
        return @f(ϵ̄, i)
    else
        return sqrt(@f(σ̄,i)*@f(σ̄,j))/@f(σ̄,i,j) * sqrt(@f(ϵ̄,i)*@f(ϵ̄,j))
    end
end

function λ̄a(model::SAFTgammaMieModel, V, T, z, i)
    λa = model.params.lambda_a.values
    return ∑(∑(@f(ẑ,i,k)*@f(ẑ,i,l)*λa[k,l] for l ∈ @groups) for k ∈ @groups)
end

function λ̄r(model::SAFTgammaMieModel, V, T, z, i)
    λr = model.params.lambda_r.values
    return ∑(∑(@f(ẑ,i,k)*@f(ẑ,i,l)*λr[k,l] for l ∈ @groups) for k ∈ @groups)
end

function g_Mie(model::SAFTgammaMieModel, V, T, z, i)
    ϵ̄_=@f(ϵ̄,i)
    g_HSi = @f(g_HS,i)
    return g_HSi*exp(ϵ̄_/T*@f(g_1,i)/g_HSi+(ϵ̄_/T)^2*@f(g_2,i)/g_HSi)
end

function g_HS(model::SAFTgammaMieModel, V, T, z, i)
    x̄_0 = @f(σ̄,i)/@f(d̄,i)
    ζ_X_ = @f(ζ_X)
    k_0 = -log(1-ζ_X_) + (42ζ_X_-39ζ_X_^2+9ζ_X_^3-2ζ_X_^4)/(6*(1-ζ_X_)^3)
    k_1 = (ζ_X_^4+6ζ_X_^2-12ζ_X_)/(2*(1-ζ_X_)^3)
    k_2 = -3ζ_X_^2/(8(1-ζ_X_)^2)
    k_3 = (-ζ_X_^4+3ζ_X_^2+3ζ_X_)/(6(1-ζ_X_)^3)
    return exp(k_0+k_1*x̄_0+k_2*x̄_0^2+k_3*x̄_0^3)
end

function g_1(model::SAFTgammaMieModel, V, T, z, i)
    λ̄a_ = @f(λ̄a,i)
    λ̄r_ = @f(λ̄r,i)
    σ̄_ = @f(σ̄,i)
    ϵ̄_ = @f(ϵ̄,i)
    d̄_ = @f(d̄,i)
    ρ_S_ = @f(ρ_S)
    x̄_0 = σ̄_/@f(d̄,i)
    C̄_ = @f(C,λ̄a_,λ̄r_)
    return 1/(2π*ϵ̄_*d̄_^3*ρ_S_)*(3*@f(∂ā_1╱∂ρ_S,i) - C̄_*λ̄a_*x̄_0^λ̄a_*(@f(āS_1,i,λ̄a_)+@f(B̄,i,λ̄a_)) + C̄_*λ̄r_*x̄_0^λ̄r_*(@f(āS_1,i,λ̄r_)+@f(B̄,i,λ̄r_)))
end

function g_2(model::SAFTgammaMieModel, V, T, z, i)
    return (1+@f(γ_c,i))*@f(gMCA_2,i)
end

function γ_c(model::SAFTgammaMieModel, V, T, z, i)
    λ̄a_ = @f(λ̄a,i)
    λ̄r_ = @f(λ̄r,i)
    ϵ̄_ = @f(ϵ̄,i)
    ᾱ = @f(C,λ̄a_,λ̄r_)*(1/(λ̄a_-3)-1/(λ̄r_-3))
    θ = exp(ϵ̄_/T)-1
    ζst_X_ = @f(ζst_X)
    return 10 * (-tanh(10*(0.57-ᾱ))+1) * ζst_X_*θ*exp(-6.7*ζst_X_-8ζst_X_^2)
end

function gMCA_2(model::SAFTgammaMieModel, V, T, z, i)
    ϵ̄_ = @f(ϵ̄,i)
    σ̄_ = @f(σ̄,i)
    d̄_ = @f(d̄,i)
    x̄_0 = σ̄_/d̄_
    λ̄a_ = @f(λ̄a,i)
    λ̄r_ = @f(λ̄r,i)
    ρ_S_ = @f(ρ_S)
    C̄_ = @f(C,λ̄a_,λ̄r_)
    KHS_ = @f(KHS)
    return 1/(2π*ϵ̄_^2*d̄_^3*ρ_S_)*(3*@f(∂ā_2╱∂ρ_S,i)-
        ϵ̄_*KHS_*C̄_^2*λ̄r_*x̄_0^(2λ̄r_)*(@f(āS_1,i,2λ̄r_)+@f(B̄,i,2λ̄r_))+
        ϵ̄_*KHS_*C̄_^2*(λ̄a_+λ̄r_)*x̄_0^(λ̄a_+λ̄r_)*(@f(āS_1,i,λ̄a_+λ̄r_)+@f(B̄,i,λ̄a_+λ̄r_))-
        ϵ̄_*KHS_*C̄_^2*λ̄a_*x̄_0^(2λ̄a_)*(@f(āS_1,i,2λ̄a_)+@f(B̄,i,2λ̄a_)))
end

function B̄(model::SAFTgammaMieModel, V, T, z, i, λ̄)
    ϵ̄_ = @f(ϵ̄,i)
    σ̄_ = @f(σ̄,i)
    d̄_ = @f(d̄,i)
    x̄_0 = σ̄_/d̄_
    ζ_X_ = @f(ζ_X)
    I = (1-x̄_0^(3-λ̄))/(λ̄-3)
    J = (1-x̄_0^(4-λ̄)*(λ̄-3)+x̄_0^(3-λ̄)*(λ̄-4))/((λ̄-3)*(λ̄-4))
    return 2π*@f(ρ_S)*d̄_^3*ϵ̄_ * ((1-ζ_X_/2)/(1-ζ_X_)^3*I-9ζ_X_*(1+ζ_X_)/(2(1-ζ_X_)^3)*J)
end

function ∂B╱∂ρ_S(model::SAFTgammaMieModel, V, T, z, i, λ̄)
    ϵ̄_ = @f(ϵ̄,i)
    σ̄_ = @f(σ̄,i)
    d̄_ = @f(d̄,i)
    x̄_0 = σ̄_/d̄_
    ζ_X_ = @f(ζ_X)
    I = (1-x̄_0^(3-λ̄))/(λ̄-3)
    J = (1-x̄_0^(4-λ̄)*(λ̄-3)+x̄_0^(3-λ̄)*(λ̄-4))/((λ̄-3)*(λ̄-4))
    return @f(B̄,i,λ̄) + 2π*@f(ρ_S)*d̄_^3*ϵ̄_ * ζ_X_*((3*(1-ζ_X_/2)*(1-ζ_X_)^2
            -0.5*(1-ζ_X_)^3)*I/(1-ζ_X_)^6-9*J*((1+2*ζ_X_)*(1-ζ_X_)^3+ζ_X_*(1+ζ_X_)*3*(1-ζ_X_)^2)/(2*(1-ζ_X_)^6))
end

function ā_1(model::SAFTgammaMieModel, V, T, z, i)
    λ̄a_ = @f(λ̄a,i)
    λ̄r_ = @f(λ̄r,i)
    x̄_0 = @f(σ̄,i)/@f(d̄,i)
    return @f(C,λ̄a_,λ̄r_)*(x̄_0^λ̄a_*(@f(āS_1,i,λ̄a_)+@f(B̄,i,λ̄a_))-x̄_0^λ̄r_*(@f(āS_1,i,λ̄r_)+@f(B̄,i,λ̄r_)))
end

function ∂ā_1╱∂ρ_S(model::SAFTgammaMieModel, V, T, z, i)
    λ̄a_ = @f(λ̄a,i)
    λ̄r_ = @f(λ̄r,i)
    x̄_0 = @f(σ̄,i)/@f(d̄,i)
    return @f(C,λ̄a_,λ̄r_)*(x̄_0^λ̄a_*(@f(∂āS_1╱∂ρ_S,i,λ̄a_)+@f(∂B╱∂ρ_S,i,λ̄a_))
                          - x̄_0^λ̄r_*(@f(∂āS_1╱∂ρ_S,i,λ̄r_)+@f(∂B╱∂ρ_S,i,λ̄r_)))
end

function āS_1(model::SAFTgammaMieModel, V, T, z, i, λ̄)
    ϵ̄_ = @f(ϵ̄,i)
    σ̄_ = @f(σ̄,i)
    d̄_ = @f(d̄,i)
    ζ̄eff_ = @f(ζeff, λ̄)
    return -2π*@f(ρ_S) * ϵ̄_*d̄_^3/(λ̄-3) * (1-ζ̄eff_/2)/(1-ζ̄eff_)^3
end

function ∂āS_1╱∂ρ_S(model::SAFTgammaMieModel, V, T, z, i, λ̄)
    ϵ̄_ = @f(ϵ̄,i)
    σ̄_ = @f(σ̄,i)
    d̄_ = @f(d̄,i)
    ζ̄eff_ = @f(ζeff, λ̄)
    A = SAFTγMieconsts.A
    ζ_X_ = @f(ζ_X)
    ∂ζ̄eff╱∂ρ_S = A * [1; 1/λ̄; 1/λ̄^2; 1/λ̄^3] ⋅ [1; 2ζ_X_; 3ζ_X_^2; 4ζ_X_^3]
    return @f(āS_1,i,λ̄) - 2π*(ϵ̄_*d̄_^3)/(λ̄-3) *@f(ρ_S)* ((3*(1-ζ̄eff_/2)*(1-ζ̄eff_)^2-1/2*(1-ζ̄eff_)^3)/(1-ζ̄eff_)^6 * ∂ζ̄eff╱∂ρ_S*ζ_X_)
end


function ∂ā_2╱∂ρ_S(model::SAFTgammaMieModel, V, T, z, i)
    ϵ̄_ = @f(ϵ̄,i)
    σ̄_ = @f(σ̄,i)
    d̄_ = @f(d̄,i)
    x̄_0 = σ̄_/d̄_
    ζ_X_ = @f(ζ_X)
    ρ_S_ = @f(ρ_S)
    ∂KHS╱∂ρ_S = -(4*(1-ζ_X_)^3*(1+4ζ_X_+4ζ_X_^2-4ζ_X_^3+ζ_X_^4)+(1-ζ_X_)^4*(4+8ζ_X_-12ζ_X_^2+4ζ_X_^3))/(1+4ζ_X_+4ζ_X_^2-4ζ_X_^3+ζ_X_^4)^2*ζ_X_
    λ̄a_ = @f(λ̄a,i)
    λ̄r_ = @f(λ̄r,i)
    return 1/2*ϵ̄_*@f(C,λ̄a_,λ̄r_)^2*(∂KHS╱∂ρ_S*(x̄_0^(2λ̄a_)*(@f(āS_1,i,2λ̄a_)+@f(B̄,i,2λ̄a_))
        -2x̄_0^(λ̄a_+λ̄r_)*(@f(āS_1,i,λ̄a_+λ̄r_)+@f(B̄,i,λ̄a_+λ̄r_))
        +x̄_0^(2λ̄r_)*(@f(āS_1,i,2λ̄r_)+@f(B̄,i,2λ̄r_)))
        +@f(KHS)*(x̄_0^(2λ̄a_)*(@f(∂āS_1╱∂ρ_S,i,2λ̄a_)+@f(∂B╱∂ρ_S,i,2λ̄a_))
        -2x̄_0^(λ̄a_+λ̄r_)*(@f(∂āS_1╱∂ρ_S,i,λ̄a_+λ̄r_)+@f(∂B╱∂ρ_S,i,λ̄a_+λ̄r_))
        +x̄_0^(2λ̄r_)*(@f(∂āS_1╱∂ρ_S,i,2λ̄r_)+@f(∂B╱∂ρ_S,i,2λ̄r_))))
end

function X(model::SAFTgammaMieModel, V, T, z)
    _1 = one(V+T+first(z))
    x = z/∑(z)
    ρ = ∑(z)*N_A/V
    v = model.allcomponentnflattenedgroups
    n = model.allgroupnsites
    itermax = 1000
    damping_factor = 0.5
    error = 1.
    tol = model.absolutetolerance
    iter = 1
    X_ = [[[_1 for a ∈ @sites(k)] for k ∈ @groups] for i ∈ @comps]
    X_old = deepcopy(X_)
    while error > tol
        if iter > itermax
            error("X has failed to converge after $itermax iterations")
        end
        for i ∈ @comps, k ∈ @groups(i), a ∈ @sites(k)
            rhs = 1/(1+ρ*∑(x[j] * ∑(v[j][l] * ∑(n[l][b] * X_old[j][l][b] * @f(Δ,i,j,k,l,a,b) for b ∈ @sites(l)) for l ∈ @groups(j)) for j ∈ @comps))
            X_[i][k][a] = (1-damping_factor)*X_old[i][k][a] + damping_factor*rhs
        end
        error = sqrt(∑(∑(∑((X_[i][k][a]-X_old[i][k][a])^2 for a ∈ @sites(k)) for k ∈ @groups(i)) for i ∈ @comps))
        for i = 1:length(X_)
            for j in 1:length(X_[i])
            X_old[i][j] .= X_[i][j]
            end
        end
        iter += 1
    end
    #println("Debug: X converged after ", iter, " iterations.")
    return X_
end

function Δ(model::SAFTgammaMieModel, V, T, z, i, j, k, l, a, b)
    σ = model.params.sigma.values
    σ3_x = ∑(∑(@f(x_S,k)*@f(x_S,l)*σ[k,l]^3 for k ∈ @groups) for l ∈ @groups)
    ϵ̄_ = @f(ϵ̄,i,j)
    ρR = @f(ρ_S)*σ3_x
    TR = T/ϵ̄_
    c  = SAFTγMieconsts.c
    I = ∑(∑(c[n+1,m+1]*ρR^n*TR^m for m in 0:(10-n)) for n in 0:10)

    ϵHB = model.params.epsilon_assoc.values
    K = model.params.bondvol.values
    F = (exp(ϵHB[k,l][a,b]/T)-1)
    return F*K[k,l][a,b]*I
end

const SAFTγMieconsts =(
    A = [ 0.81096    1.7888   -37.578   92.284;
          1.02050  -19.341    151.26  -463.50 ;
         -1.90570   22.845   -228.14   973.92 ;
          1.08850   -6.1962   106.98  -677.64  ],

    ϕ = [[7.5365557, -359.440,  1550.9, -1.199320, -1911.2800,  9236.9  ],
        [-37.604630,  1825.60, -5070.1,  9.063632,  21390.175, -129430 ],
        [71.745953, -3168.00,  6534.6, -17.94820, -51320.700,  357230  ],
        [-46.835520,  1884.20, -3288.7,  11.34027,  37064.540, -315530 ],
        [-2.4679820,- 0.82376, -2.7171,  20.52142,  1103.7420,  1390.2 ],
        [-0.5027200, -3.19350,  2.0883, -56.63770, -3264.6100, -4518.2 ],
        [8.0956883,  3.70900,  0.0000,  40.53683,  2556.1810,  4241.6  ]],

    u = [0.26356031971814109102031,1.41340305910651679221800,3.59642577104072208122300,7.08581000585883755692200,12.6408008442757826594300],
    w = [0.5217556105828086524759,0.3986668110831759274500,7.5942449681707595390e-2,3.6117586799220484545e-3,2.3369972385776227891e-5],

         c  = [0.0756425183020431	-0.128667137050961	 0.128350632316055	-0.0725321780970292	   0.0257782547511452  -0.00601170055221687	  0.000933363147191978  -9.55607377143667e-05  6.19576039900837e-06 -2.30466608213628e-07 3.74605718435540e-09
                0.134228218276565	    -0.182682168504886 	 0.0771662412959262	-0.000717458641164565 -0.00872427344283170	0.00297971836051287	 -0.000484863997651451	 4.35262491516424e-05 -2.07789181640066e-06	4.13749349344802e-08 0
               -0.565116428942893	     1.00930692226792   -0.660166945915607	 0.214492212294301	  -0.0388462990166792	0.00406016982985030	 -0.000239515566373142	 7.25488368831468e-06 -8.58904640281928e-08	0	                 0
               -0.387336382687019	    -0.211614570109503	 0.450442894490509	-0.176931752538907	   0.0317171522104923  -0.00291368915845693	  0.000130193710011706  -2.14505500786531e-06  0	                0	                 0
                2.13713180911797	    -2.02798460133021 	 0.336709255682693	 0.00118106507393722  -0.00600058423301506	0.000626343952584415 -2.03636395699819e-05	 0	                   0	                0	                 0
               -0.300527494795524	     2.89920714512243   -0.567134839686498	 0.0518085125423494	  -0.00239326776760414	4.15107362643844e-05  0	                     0	                   0	                0                    0
               -6.21028065719194	    -1.92883360342573	 0.284109761066570	-0.0157606767372364	   0.000368599073256615	0 	                  0	                     0	                   0	                0	                 0
                11.6083532818029	     0.742215544511197  -0.0823976531246117	 0.00186167650098254   0	                0	                  0	                     0	                   0	                0	                 0
               -10.2632535542427	    -0.125035689035085	 0.0114299144831867	 0	                   0	                0	                  0	                     0	                   0	                0	                 0
                4.65297446837297	    -0.00192518067137033 0	                 0	                   0	                0	                  0	                     0	                   0	                0	                 0
               -0.867296219639940	     0	                 0	                 0	                   0	                0	                  0	                     0	                   0	                0	                 0],
)
