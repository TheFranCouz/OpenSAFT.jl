struct CKSAFTParam <: EoSParam
    segment::SingleParam{Float64}
    sigma::PairParam{Float64}
    epsilon::PairParam{Float64}
    c::SingleParam{Float64}
    epsilon_assoc::AssocParam{Float64}
    bondvol::AssocParam{Float64}
end

abstract type CKSAFTModel <: SAFTModel end
@newmodel CKSAFT CKSAFTModel CKSAFTParam

export CKSAFT
function CKSAFT(components::Array{String,1}; idealmodel=BasicIdeal, userlocations::Array{String,1}=String[], verbose=false)
    params = getparams(components, ["SAFT/CKSAFT","properties/molarmass.csv"]; userlocations=userlocations, verbose=verbose)
    segment = params["m"]
    c = params["c"]
    k = params["k"]
    sigma = params["vol"]
    sigma.values .*= 6*0.74048/N_A/1e6/π
    sigma.values .^= 1/3
    sigma = sigma_LorentzBerthelot(sigma)
    epsilon = epsilon_LorentzBerthelot(params["epsilon"], k)
    epsilon_assoc = params["epsilon_assoc"]
    bondvol = params["bond_vol"]
    sites = SiteParam(Dict("e" => params["n_e"], "H" => params["n_H"]))

    packagedparams = CKSAFTParam(segment, sigma, epsilon,c, epsilon_assoc, bondvol)
    references = ["TODO CKSAFT", "TODO CKSAFT"]

    model = CKSAFT(packagedparams, sites, idealmodel; references=references, verbose=verbose)
    return model
end

function a_res(model::CKSAFTModel, V, T, z)
    return @f(a_seg) + @f(a_chain) + @f(a_assoc)
end

function a_seg(model::CKSAFTModel, V, T, z)
    x = z/∑(z)
    m = model.params.segment.values
    m̄ = mixing_rule_quad((x,y)->0.5*(x+y), x,m)
    return m̄*(@f(a_hs) + @f(a_disp))
end

function a_hs(model::CKSAFTModel, V, T, z)
    ζ0 = @f(ζ,0)
    ζ1 = @f(ζ,1)
    ζ2 = @f(ζ,2)
    ζ3 = @f(ζ,3)
    return 1/ζ0 * (3ζ1*ζ2/(1-ζ3) + ζ2^3/(ζ3*(1-ζ3)^2) + (ζ2^3/ζ3^2-ζ0)*log(1-ζ3))
end

function a_disp(model::CKSAFTModel, V, T, z)
    x = z/∑(z)
    ϵ̄ = @f(ū)
    η = @f(ζ,3)
    τ = 0.74048
    D1 = CKSAFT_consts.D1
    D2 = CKSAFT_consts.D2
    D3 = CKSAFT_consts.D3
    D4 = CKSAFT_consts.D4
    eT = (ϵ̄/T)
    A1 = ∑(D1[j]*eT*(η/τ)^j for j ∈ 1:6)
    A2 = ∑(D2[j]*eT^2*(η/τ)^j for j ∈ 1:9)
    A3 = ∑(D3[j]*eT^3*(η/τ)^j for j ∈ 1:5)
    A4 = ∑(D4[j]*eT^4*(η/τ)^j for j ∈ 1:4)
    return A1+A2+A3+A4
end

function d(model::CKSAFTModel, V, T,z, i)
    ϵ = model.params.epsilon.diagvalues[i]
    σ = model.params.sigma.diagvalues[i]
    return σ * (1 - 0.12exp(-3ϵ/T))
end

function d(model::CKSAFTModel, V, T, z, i,j)
    #return (d(model::CKSAFTModel, z, v, T, i)+d(model::CKSAFTModel, z, v, T, j))/2
    return (@f(d,i) + @f(d,j))*0.5
end

function u(model::CKSAFTModel, V, T, z, i,j)
    ϵ0 = model.params.epsilon.values[i,j]
    c1 = model.params.c.values[i]
    c2 = model.params.c.values[j]
    return ϵ0*sqrt((1+c1/T)*(1+c2/T))
end

function ū(model::CKSAFTModel, V, T, z)
    Σz = ∑(z)
    x = z.*(1/Σz)
    it = @comps #only to stop vscode from recognizing this as an error
    m = model.params.segment.values
    num = ∑(
            x[i]*x[j]*m[i]*m[j]*@f(u,i,j)*@f(d,i,j)^3
            for i ∈ it for j ∈ it)

    denom = ∑(
            x[i]*x[j]*m[i]*m[j]*@f(d,i,j)^3
            for i ∈ it for j ∈ it)
    return num/denom
end

function ζ(model::CKSAFTModel, V, T, z, n)
    ∑z = ∑(z)
    x = z.*(1/∑z)
    m = model.params.segment.values
    return N_A*∑z*π/6/V * ∑(x[i]*m[i]*@f(d,i)^n for i ∈ @comps)
end

function a_chain(model::CKSAFTModel, V, T, z)
    x = z/∑(z)
    m = model.params.segment.values
    return ∑(x[i]*(1-m[i])*log(@f(g_hsij,i,i)) for i ∈ @comps)
end

function g_hsij(model::CKSAFTModel, V, T, z, i, j)
    di = @f(d,i)
    dj = @f(d,j)
    ζ2 = @f(ζ,2)
    ζ3 = @f(ζ,3)
    return 1/(1-ζ3) + di*dj/(di+dj)*3ζ2/(1-ζ3)^2 + (di*dj/(di+dj))^2*2ζ2^2/(1-ζ3)^3
end

function a_assoc(model::CKSAFTModel, V, T, z)
    x = z/∑(z)
    X_ = @f(X_assoc)
    n = model.allcomponentnsites
    #return ∑(x[i]*∑(log(X_iA[i,a])-X_iA[i,a]/2 + model.params.n_sites[i][a]/2 for a ∈ keys(model.params.n_sites[i])) for i ∈ model.components)
    return ∑(x[i]*
                ∑(
                  n[i][a]*(log(X_[i][a]) - X_[i][a]/2 + 0.5)
                for a ∈ @sites(i))
            for i ∈ @comps)
end

function X_assoc(model::CKSAFTModel, V, T, z)
    _1 = one(V+T+first(z))
    Σz = ∑(z)
    x = z/ Σz
    ρ = N_A* Σz/V
    itermax = 100
    dampingfactor = 0.5
    error = 1.
    tol = model.absolutetolerance
    iter = 20
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
        @show X_
    end
    return X_
end

function Δ(model::CKSAFTModel, V, T, z, i, j, a, b)
    ϵ_associjab = model.params.epsilon_assoc.values[i,j][a,b]
    κijab = model.params.bondvol.values[i,j][a,b]
    σij = model.params.sigma.values[i,j]
    gij = @f(g_hsij,i,j)
    return gij*σij^3*(exp(ϵ_associjab/T)-1)*κijab
end

const CKSAFT_consts =(
    D1 = [-8.8043,4.164627,-48.203555,140.4362,-195.23339,113.515],
    D2 = [2.9396,-6.0865383,40.137956,-76.230797,-133.70055,860.25349,-1535.3224,1221.4261,-409.10539],
    D3 = [-2.8225,4.7600148,11.257177,-66.382743,69.248785],
    D4 = [0.34,-3.1875014,12.231796,-12.110681],
    D =
    [0.9105631445 -0.3084016918 -0.0906148351;
    0.6361281449 0.1860531159 0.4527842806;
    2.6861347891 -2.5030047259 0.5962700728;
    -26.547362491 21.419793629 -1.7241829131;
    97.759208784 -65.255885330 -4.1302112531;
    -159.59154087 83.318680481 13.776631870;
    91.297774084 -33.746922930 -8.6728470368],
)
