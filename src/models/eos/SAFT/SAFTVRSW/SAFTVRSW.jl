struct SAFTVRSWParam <: EoSParam
    segment::SingleParam{Float64}
    sigma::PairParam{Float64}
    lambda::PairParam{Float64}
    epsilon::PairParam{Float64}
    epsilon_assoc::AssocParam{Float64}
    bondvol::AssocParam{Float64}
end

abstract type SAFTVRSWModel <: SAFTModel end
@newmodel SAFTVRSW SAFTVRSWModel SAFTVRSWParam

export SAFTVRSW
function SAFTVRSW(components::Array{<:Any,1}; idealmodel::Type=BasicIdeal, userlocations::Array{String,1}=String[], verbose=false)
    params = getparams(components, ["SAFT/SAFTVRSW"]; userlocations=userlocations, verbose=verbose)

    segment = params["m"]
    k = params["k"]
    params["sigma"].values .*= 1E-10
    sigma = sigma_LorentzBerthelot(params["sigma"])
    epsilon = epsilon_LorentzBerthelot(params["epsilon"], k)
    lambda = lambda_squarewell(params["lambda"], sigma)

    epsilon_assoc = params["epsilon_assoc"]
    bondvol = params["bondvol"]
    sites = SiteParam(Dict("e" => params["n_e"], "H" => params["n_H"]))

    packagedparams = SAFTVRSWParam(segment, sigma, lambda, epsilon, epsilon_assoc, bondvol)
    references = ["todo"]

    model = SAFTVRSW(packagedparams, sites, idealmodel; references=references, verbose=verbose)
    return model
end

function a_res(model::SAFTVRSWModel, V, T, z)
    return @f(a_mono) + @f(a_chain) + @f(a_assoc)
end

function a_mono(model::SAFTVRSWModel, V, T, z)
    return @f(a_hs) + @f(a_disp)
end

function a_disp(model::SAFTVRSWModel, V, T, z)
    return @f(a_1) + @f(a_2)
end

function a_hs(model::SAFTVRSWModel, V, T, z)
    ζ0 = @f(ζn,0)
    ζ1 = @f(ζn,1)
    ζ2 = @f(ζn,2)
    ζ3 = @f(ζn,3)
    x = z/∑(z)
    m = model.params.segment.values
    m̄ = ∑(x .* m)
    return m̄*6/π/@f(ρ_S)*(3ζ1*ζ2/(1-ζ3) + ζ2^3/(ζ3*(1-ζ3)^2) + (ζ2^3/ζ3^2-ζ0)*log(1-ζ3))
end

function ζn(model::SAFTVRSWModel, V, T, z, n)
    σ = model.params.sigma.diagvalues
    return π/6*@f(ρ_S)*∑(@f(x_S,i)*σ[i]^n for i ∈ @comps)
end

function ρ_S(model::SAFTVRSWModel, V, T, z)
    ∑z = ∑(z)
    N = N_A*∑z
    x = z/∑z
    m = model.params.segment.values
    m̄ = ∑(x .* m)
    return N/V*m̄
end

function x_S(model::SAFTVRSWModel, V, T, z, i)
    x = z/∑(z)
    m = model.params.segment.values
    m̄ = ∑(x .* m)
    return x[i]*m[i]/m̄
end

function ζ_X(model::SAFTVRSWModel, V, T, z)
    σ = model.params.sigma.values
    return π/6*@f(ρ_S)*∑(@f(x_S,i)*@f(x_S,j)*σ[i,j]^3 for i ∈ @comps for j ∈ @comps)
end

function a_1(model::SAFTVRSWModel, V, T, z)
    x = z/∑(z)
    m = model.params.segment.values
    m̄ = ∑(x .* m)
    return -m̄/T*@f(ρ_S)*∑(@f(x_S,i)*@f(x_S,j)*@f(a_1,i,j) for i ∈ @comps for j ∈ @comps)
end

function a_1(model::SAFTVRSWModel, V, T, z, i, j)
    ϵ = model.params.epsilon.values
    λ = model.params.lambda.values
    σ = model.params.sigma.values
    αVDWij = 2π*ϵ[i,j]*σ[i,j]^3*(λ[i,j]^3-1)/3
    return αVDWij * @f(gHS_0,i,j)
end

function ζeff_X(model::SAFTVRSWModel, V, T, z, λ)
    A = SAFTVRSWconsts.A
    ζ_X_ = @f(ζ_X)
    return A * [1; λ; λ^2] ⋅ [ζ_X_; ζ_X_^2; ζ_X_^3]
end

function gHS_0(model::SAFTVRSWModel,V, T, z, i, j)
    λ = model.params.lambda.values
    ζeff_X_ = @f(ζeff_X,λ[i,j])
    return (1-ζeff_X_/2)/(1-ζeff_X_)^3
end

function a_2(model::SAFTVRSWModel, V, T, z)
    x = z/∑(z)
    m = model.params.segment.values
    m̄ = ∑(x .* m)
    return m̄/T^2*∑(@f(x_S,i)*@f(x_S,j)*@f(a_2,i,j) for i ∈ @comps for j ∈ @comps)
end

function a_2(model::SAFTVRSWModel, V, T, z, i, j)
    ϵ = model.params.epsilon.values
    ζ0 = @f(ζn,0)
    ζ1 = @f(ζn,1)
    ζ2 = @f(ζn,2)
    ζ3 = @f(ζn,3)
    KHS = ζ0*(1-ζ3)^4/(ζ0*(1-ζ3)^2+6*ζ1*ζ2*(1-ζ3)+9*ζ2^3)
    return 1/2*KHS*ϵ[i,j]*@f(ρ_S)*@f(∂a_1╱∂ρ_S,i,j)
end

function ∂a_1╱∂ρ_S(model::SAFTVRSWModel, V, T, z, i, j)
    ϵ = model.params.epsilon.values
    λ = model.params.lambda.values
    σ = model.params.sigma.values
    αij = 2π*ϵ[i,j]*σ[i,j]^3*(λ[i,j]^3-1)/3
    ζ_X_ = @f(ζ_X)
    ζeff_X_ = @f(ζeff_X,λ[i,j])
    A = SAFTVRSWconsts.A
    # ∂ζeff_X╱∂ζ_X = A * [1; λ[i,j]; λ[i,j]^2] ⋅ [ζ_X_; 2ζ_X_^2; 3ζ_X_^3]
    ∂ζeff_X╱∂ζ_X = A * [1; λ[i,j]; λ[i,j]^2] ⋅ [1; 2ζ_X_; 3ζ_X_^2]
    return -αij*(@f(gHS_0,i,j)+(5/2-ζeff_X_)/(1-ζeff_X_)^4*∂ζeff_X╱∂ζ_X)
end

function a_chain(model::SAFTVRSWModel, V, T, z)
    x = z/∑(z)
    m = model.params.segment.values
    return -∑(x[i]*(log(@f(γSW,i))*(m[i]-1)) for i ∈ @comps)
end

function γSW(model::SAFTVRSWModel,V, T, z, i)
    ϵ = model.params.epsilon.diagvalues
    return @f(gSW,i,i)*exp(-ϵ[i]/T)
end

function gSW(model::SAFTVRSWModel,V, T, z, i, j)
    ϵ = model.params.epsilon.values
    return @f(gHS,i,j)+ϵ[i,j]/T*@f(g_1,i,j)
end

function gHS(model::SAFTVRSWModel,V, T, z, i, j)
    σ = model.params.sigma.values
    ζ3 = @f(ζn,3)
    D = σ[i]*σ[j]/(σ[i]+σ[j])*∑(@f(x_S,k)*σ[k]^2 for k ∈ @comps)/∑(@f(x_S,k)*σ[k]^3 for k ∈ @comps)
    return 1/(1-ζ3)+3*D*ζ3/(1-ζ3)^2+2*(D*ζ3)^2/(1-ζ3)^3
end

function g_1(model::SAFTVRSWModel,V, T, z, i, j)
    λ = model.params.lambda.values
    ζ_X_ = @f(ζ_X)
    ζeff_X_ = @f(ζeff_X,λ[i,j])
    A = SAFTVRSWconsts.A
    ∂ζeff_X╱∂ζ_X = A * [1; λ[i,j]; λ[i,j]^2] ⋅ [1; 2ζ_X_; 3ζ_X_^2]
    ∂ζeff_X╱∂λ = A * [0; 1; 2λ[i,j]] ⋅ [ζ_X_; ζ_X_^2; ζ_X_^3]
    return @f(gHS_0,i,j)+(λ[i,j]^3-1)*(5/2-ζeff_X_)/(1-ζeff_X_)^4*(λ[i,j]/3*∂ζeff_X╱∂λ-ζ_X_*∂ζeff_X╱∂ζ_X)
end

function a_assoc(model::SAFTVRSWModel, V, T, z)
    x = z/∑(z)
    n = model.allcomponentnsites
    X_ = @f(X)
    return ∑(x[i]*∑(n[i][a]*(log(X_[i][a])+(1-X_[i][a])/2) for a ∈ @sites(i)) for i ∈ @comps)
end

function X(model::SAFTVRSWModel, V, T, z)
    _1 = one(V+T+first(z))
    ∑z = ∑(z)
    x = z/∑z
    ρ = N_A*∑z/V
    n = model.allcomponentnsites
    itermax = 500
    dampingfactor = 0.5
    error = 1.
    tol = model.absolutetolerance
    iter = 1
    X_ = [[_1 for a ∈ @sites(i)] for i ∈ @comps]
    X_old = deepcopy(X_)
    while error > tol
        iter > itermax && error("X has failed to converge after $itermax iterations")
        for i ∈ @comps, a ∈ @sites(i)
            rhs = 1/(1+∑(ρ*x[j]*∑(n[j][b]*X_old[j][b]*@f(Δ,i,j,a,b) for b ∈ @sites(j)) for j ∈ @comps))
            X_[i][a] = (1-dampingfactor)*X_old[i][a] + dampingfactor*rhs
        end
        error = sqrt(∑(∑((X_[i][a] - X_old[i][a])^2 for a ∈ @sites(i)) for i ∈ @comps))
        for i = 1:length(X_)
            X_old[i] .= X_[i]
        end
        X_
        iter += 1
    end
    return X_
end

function Δ(model::SAFTVRSWModel, V, T, z, i, j, a, b)
    ϵ_assoc = model.params.epsilon_assoc.values
    κ = model.params.bondvol.values
    g = @f(gSW,i,j)
    return g*(exp(ϵ_assoc[i,j][a,b]/T)-1)*κ[i,j][a,b]
end

const SAFTVRSWconsts = (
    A = [2.25855   -1.50349  0.249434;
    -0.66927  1.40049   -0.827739;
    10.1576   -15.0427   5.30827],
)
