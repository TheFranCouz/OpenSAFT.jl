struct ogSAFTParam <: EoSParam
    segment::SingleParam{Float64}
    sigma::PairParam{Float64}
    epsilon::PairParam{Float64}
    epsilon_assoc::AssocParam{Float64}
    bondvol::AssocParam{Float64}
end

abstract type ogSAFTModel <: SAFTModel end
@newmodel ogSAFT ogSAFTModel ogSAFTParam

export ogSAFT
function ogSAFT(components::Array{String,1}; idealmodel=BasicIdeal, userlocations::Array{String,1}=String[], verbose=false)
    params = getparams(components, ["SAFT/ogSAFT"]; userlocations=userlocations, verbose=verbose)
    segment = params["m"]
    k = params["k"]
    params["sigma"].values .*= 1E-10
    sigma = sigma_LorentzBerthelot(params["sigma"])
    epsilon = epsilon_LorentzBerthelot(params["epsilon"], k)
    epsilon_assoc = params["epsilon_assoc"]
    bondvol = params["bondvol"]
    sites = SiteParam(Dict("e" => params["n_e"], "H" => params["n_H"]))

    packagedparams = ogSAFTParam(segment, sigma, epsilon, epsilon_assoc, bondvol)
    references = ["todo"]

    model = ogSAFT(packagedparams, sites, idealmodel; references=references, verbose=verbose)
    return model
end

function a_res(model::ogSAFTModel, V, T, z)
    return @f(a_seg) + @f(a_chain) + @f(a_assoc)
end

function a_seg(model::ogSAFTModel, V, T, z)
    x = z/∑(z)
    m = model.params.segment.values
    m̄ = ∑(x .* m)
    return m̄*(@f(a_hs)+@f(a_disp))
end

function a_chain(model::ogSAFTModel, V, T, z)
    x = z/∑(z)
    m = model.params.segment.values
    return ∑(x[i]*(1-m[i])*log(@f(g_hsij, i, i)) for i ∈ @comps)
end

function d(model::ogSAFTModel, V, T, z, i)
    ϵ = model.params.epsilon.diagvalues
    σ = model.params.sigma.diagvalues
    m = model.params.segment.values
    fm = 0.0010477+0.025337*(m[i]-1)/m[i]
    f = (1+0.2977T/ϵ[i])/(1+0.33163T/ϵ[i]+fm*(T/ϵ[i])^2)
    return σ[i] * f
end

function dx(model::ogSAFTModel, V, T, z)
    x = z/∑(z)
    m = model.params.segment.values
    σ = model.params.sigma.values
    ϵ = model.params.epsilon.values

    mx = ∑(x .* m)
    σx = (∑(x[i]*x[j]*m[i]*m[j]*σ[i,j]^3 for i ∈ @comps for j ∈ @comps)/mx^2)^(1/3)
    ϵx = (∑(x[i]*x[j]*m[i]*m[j]*σ[i,j]^3*ϵ[i,j] for i ∈ @comps for j ∈ @comps)/mx^2)/σx^3

    fm = 0.0010477+0.025337*(mx-1)/mx
    f = (1+0.2977T/ϵx)/(1+0.33163T/ϵx+fm*(T/ϵx)^2)
    return σx * f
end

function ζn(model::ogSAFTModel, V, T, z, n)
    ∑z = ∑(z)
    x = z/∑z
    m = model.params.segment.values
    return N_A*∑z*π/6/V * ∑(x[i]*m[i]*@f(d, i)^n for i ∈ @comps)
end

function η(model::ogSAFTModel, V, T, z)
    ∑z = ∑(z)
    x = z/∑z
    m = model.params.segment.values
    m̄ = ∑(x .* m)
    return N_A*∑z*π/6/V*@f(dx)^3*m̄
end

function g_hsij(model::ogSAFTModel, V, T, z, i, j)
    di = @f(d,i)
    dj = @f(d,j)
    ζ2 = @f(ζn,2)
    ζ3 = @f(ζn,3)
    return 1/(1-ζ3) + di*dj/(di+dj)*3ζ2/(1-ζ3)^2 + (di*dj/(di+dj))^2*2ζ2^2/(1-ζ3)^3
end

function a_hs(model::ogSAFTModel, V, T, z)
    ηx = @f(η)
    return (4ηx-3ηx^2)/(1-ηx)^2
end

function a_disp(model::ogSAFTModel, V, T, z)
    m = model.params.segment.values
    σ = model.params.sigma.values
    ϵ = model.params.epsilon.values
    x = z/∑(z)
    ϵx = ∑(x[i]*x[j]*m[i]*m[j]*σ[i,j]^3*ϵ[i,j] for i ∈ @comps for j ∈ @comps)/∑(x[i]*x[j]*m[i]*m[j]*σ[i,j]^3 for i ∈ @comps for j ∈ @comps)
    ηx = @f(η)
    ρR = (6/sqrt(2)/π)*ηx
    TR = T/ϵx
    a_seg1 = ρR*evalpoly(ρR,(-8.5959,-4.5424,-2.1268,10.285))
    a_seg2 = ρR*evalpoly(ρR,(-1.9075,9.9724,-22.216,+15.904))
    return 1/TR*(a_seg1+a_seg2/TR)
end

## This is an attempt to make Twu et al.'s segment term; does not work yet
# function a_seg(model::ogSAFTModel, V, T, z)
#     Bo = [1.31024,-3.80636,-2.37238,-0.798872,0.198761,1.47014,-0.786367,2.19465,5.75429,6.7822,-9.94904,-15.6162,86.643,18.527,9.04755,8.68282]
#     Ba = [3.79621,-6.14518,-1.84061,-2.77584,-0.420751,-5.66128,19.2144,-3.33443,33.0305,-5.90766,9.55619,-197.883,-61.2535,77.1802,-6.57983,0.0]
#     ω = 0.011
#     A = []
#     for i ∈ 1:16
#         append!(A,Bo[i]+ω*Ba[i])
#     end
#     m = model.params.segment
#     σ = model.params.sigma
#     ϵ = model.params.epsilon
#     x = z/∑(z[i] for i ∈ @comps)
#     mx = ∑(x[i]*m[i] for i ∈ @comps)
#     σx = (∑(x[i]*x[j]*m[i]*m[j]*σ[i,j]^3 for i ∈ @comps for j ∈ @comps)/mx^2)^(1/3)
#     ϵx = (∑(x[i]*x[j]*m[i]*m[j]*σ[i,j]^3*ϵ[i,j] for i ∈ @comps for j ∈ @comps)/mx^2)/σx^3
#
#     ρ  = ∑(z)*N_A/V
#     # ρR = ρ*mx*σx^3
#     ηx = η(model,V, T, z)
#     ρR = (6/π)*ηx
#     TR = T/ϵx
#
#     u_res = (A[2]/TR+2A[3]/TR^2+3A[4]/TR^3+5A[5]/TR^5)*ρR+1/2*A[7]/TR*ρR^2+
#             1/(2*A[16])*(3A[9]/TR^3+4A[10]/TR^4+5A[11]/TR^5)*(1-exp(-A[16]*ρR^2))+
#             1/(2*A[16]^2)*(3A[12]/TR^3+4A[13]/TR^4+5A[14]/TR^5)*(1-(1+A[16]*ρR^2)*exp(-A[16]*ρR^2))+
#             1/5*A[15]/TR*ρR^5
#     s_res = -log(ρ*R̄*T)-(A[1]-A[3]/TR^2-2A[4]/TR^3-4A[5]/TR^5)*ρR-1/2*A[6]*ρR^2-1/3*A[8]*ρR^3+
#             1/(2*A[16])*(2A[9]/TR^3+3A[10]/TR^4+4A[11]/TR^5)*(1-exp(-A[16]*ρR^2))+
#             1/(2*A[16]^2)*(2A[12]/TR^3+3A[13]/TR^4+4A[14]/TR^5)*(1-(1+A[16]*ρR^2)*exp(-A[16]*ρR^2))
#     a_res = u_res-s_res
#     return mx*(a_res)
# end

function a_assoc(model::ogSAFTModel, V, T, z)
    x = z/∑(z)
    X_ = @f(X)
    n = model.allcomponentnsites
    return ∑(x[i]*∑(n[i][a] * (log(X_[i][a]) - X_[i][a]/2 + 0.5) for a ∈ @sites(i)) for i ∈ @comps)
end

function X(model::ogSAFTModel, V, T, z)
    _1 = one(V+T+first(z))
    ∑z = ∑(z)
    x = z/∑z
    ρ = N_A*∑z/V
    itermax = 100
    dampingfactor = 0.5
    error = 1.
    tol = model.absolutetolerance
    iter = 1
    X_ = [[_1 for a ∈ @sites(i)] for i ∈ @comps]
    X_old = deepcopy(X_)
    while error > tol
        iter > itermax && error("X has failed to converge after $itermax iterations")
        for i ∈ @comps, a ∈ @sites(i)
            rhs = 1/(1+∑(ρ*x[j]*∑(X_old[j][b]*@f(Δ,i,j,a,b) for b ∈ @sites(j)) for j ∈ @comps))
            X_[i][a] = (1-dampingfactor)*X_old[i][a] + dampingfactor*rhs
        end
        error = sqrt(∑(∑((X_[i][a] - X_old[i][a])^2 for a ∈ @sites(i)) for i ∈ @comps))
        for i = 1:length(X_)
            X_old[i] .= X_[i]
        end
        iter += 1
    end
    return X_
end

function Δ(model::ogSAFTModel, V, T, z, i, j, a, b)
    ϵ_assoc = model.params.epsilon_assoc.values
    κ = model.params.bondvol.values
    g = @f(g_hsij,i,j)
    return (@f(d,i)+@f(d,j))^3/2^3*g*(exp(ϵ_assoc[i,j][a,b]/T)-1)*κ[i,j][a,b]
end
