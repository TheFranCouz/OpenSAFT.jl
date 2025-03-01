struct LJSAFTParam <: EoSParam
    segment::SingleParam{Float64}
    b::PairParam{Float64}
    T_tilde::PairParam{Float64}
    epsilon_assoc::AssocParam{Float64}
    bondvol::AssocParam{Float64}
end

abstract type LJSAFTModel <: SAFTModel end
@newmodel LJSAFT LJSAFTModel LJSAFTParam

export LJSAFT
function LJSAFT(components::Array{String,1}; idealmodel=BasicIdeal, userlocations::Array{String,1}=String[], verbose=false)
    params = getparams(components, ["SAFT/LJSAFT"]; userlocations=userlocations, verbose=verbose)
    segment = params["m"]

    params["b"].values .*= 1E-3
    b = sigma_LorentzBerthelot(params["b"])
    k = params["k"]
    T_tilde = epsilon_LorentzBerthelot(params["T_tilde"], k)
    epsilon_assoc = params["epsilon_assoc"]
    bondvol = params["bondvol"]
    sites = SiteParam(Dict("e" => params["n_e"], "H" => params["n_H"]))

    packagedparams = LJSAFTParam(segment, b, T_tilde, epsilon_assoc, bondvol)
    references = ["10.1021/ie9602320"]

    model = LJSAFT(packagedparams, sites, idealmodel; references=references, verbose=verbose)
    return model
end

function a_res(model::LJSAFTModel, V, T, z)
    return @f(a_seg) + @f(a_chain) + @f(a_assoc)
end

function a_seg(model::LJSAFTModel, V, T, z)
    D = [0.011117524,-0.076383859,1.080142248, 0.000693129,-0.063920968]
    C = [-0.58544978,0.43102052,0.87361369,-4.13749995,2.90616279,-7.02181962,0.,0.0245987]
    C0 = [2.01546797,-28.17881636,28.28313847,-10.42402873]
    C1 = [-19.58371655,75.62340289,-120.70586598,93.92740328,-27.37737354]
    C2 = [29.34470520,-112.35356937,170.64908980,-123.06669187,34.42288969]
    C4 = [-13.37031968,65.38059570,-115.09233113,88.91973082,-25.62099890]
    x = z/∑(z)
    m = model.params.segment.values

    T̃ = @f(Tm)
    b̄ = @f(bm)

    Tst = T/T̃
    m̄ = ∑(m .* x)
    ρ = ∑(z)/V
    ρst = m̄*b̄*ρ
    η = ρst*π/6*(∑(D[i+3]*Tst^(i/2) for i ∈ -2:1)+D[end]*log(Tst))^3

    A_HS = Tst*(5/3*log(1-η)+(η*(34-33η+4η^2))/(6*(1-η)^2))
    ΔB2 = ∑(C[j+8]*Tst^(j/2) for j ∈ -7:0)
    A0 = ∑(C0[j-1]*ρst^j for j ∈ 2:5)
    A1 = ∑(C1[j-1]*Tst^(-1/2)*ρst^j for j ∈ 2:6)
    A2 = ∑(C2[j-1]*Tst^(-1)*ρst^j for j ∈ 2:6)
    A4 = ∑(C4[j-1]*Tst^(-2)*ρst^j for j ∈ 2:6)

    γ = 1.92907278
    return m̄*(A_HS+exp(-γ*ρst^2)*ρst*Tst*ΔB2+A0+A1+A2+A4)/Tst
end

function Tm(model::LJSAFTModel, V, T, z)
    x = z/∑(z)
    T̃ = model.params.T_tilde.values
    b = model.params.b.values
    m = model.params.segment.values
    return ∑(m[i]*m[j]*x[i]*x[j]*b[i,j]*T̃[i,j] for i ∈ @comps for j ∈ @comps)/∑(m[i]*m[j]*x[i]*x[j]*b[i,j] for i ∈ @comps for j ∈ @comps)
end

function bm(model::LJSAFTModel, V, T, z)
    x = z/∑(z)
    b = model.params.b.values
    m = model.params.segment.values
    return ∑(m[i]*m[j]*x[i]*x[j]*b[i,j] for i ∈ @comps for j ∈ @comps)/∑(m[i]*m[j]*x[i]*x[j] for i ∈ @comps for j ∈ @comps)
end

function a_chain(model::LJSAFTModel, V, T, z)
    x = z/∑(z)
    m = model.params.segment.values
    m̄ = ∑(m .* x)
    return -log(@f(g_LJ))*(m̄-1)
end

function g_LJ(model::LJSAFTModel, V, T, z)
    ∑z = ∑(z)
    x = z/∑(z)
    m = model.params.segment.values

    T̃ = @f(Tm)
    b̄ = @f(bm)

    Tst = T/T̃
    m̄ = ∑(m .* x)
    ρ = ∑z/V
    ρ̄ = m̄*b̄*ρ
    a = LJSAFTconsts.a

    return (1+∑(a[i,j]*ρ̄^i*Tst^(1-j) for i ∈ 1:5 for j ∈ 1:5))
end

function a_assoc(model::LJSAFTModel, V, T, z)
    x = z/∑(z)
    n = model.allcomponentnsites
    X_ = @f(X)
    return ∑(x[i]*∑(n[i][a]*(log(X_[i][a])+(1-X_[i][a])/2) for a ∈ @sites(i)) for i ∈ @comps)
end

function X(model::LJSAFTModel, V, T, z)
    _1 = one(V+T+first(z))
    ∑z = ∑(z)
    x = z/∑z
    ρ = ∑z/V
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
        iter += 1
    end
    return X_
end

function Δ(model::LJSAFTModel, V, T, z, i, j, a, b)
    ∑z = ∑(z)
    x = z/∑z
    m = model.params.segment.values

    T̃ = @f(Tm)
    b̄ = @f(bm)

    Tst = T/T̃
    m̄ = ∑(m .* x)
    ρ = ∑z/V
    ρ̄ = m̄*b̄*ρ
    ϵ_assoc = model.params.epsilon_assoc.values
    κ = model.params.bondvol.values
    b_ = LJSAFTconsts.b
    I = ∑(b_[i+1,j+1]*ρ̄^i*Tst^j for i ∈ 0:4 for j ∈ 0:4)/3.84/1e4
    return 4π*(exp(ϵ_assoc[i,j][a,b]/T)-1)*κ[i,j][a,b]*I*b̄
end

const LJSAFTconsts = (
    a = [0.49304346593882 2.1528349894745 -15.955682329017 24.035999666294 -8.6437958513990;
           -0.47031983115362 1.1471647487376  37.889828024211 -84.667121491179 39.643914108411;
            5.0325486243620 -25.915399226419 -18.862251310090 107.63707381726 -66.602649735720;
           -7.3633150434385  51.553565337453 -40.519369256098 -38.796692647218 44.605139198378;
            2.9043607296043 -24.478812869291  31.500186765040 -5.3368920371407 -9.5183440180133],
    b    = [-0.03915181 0.08450471 0.06889053 -0.01034279  0.5728662e-3;
             -0.5915018  0.9838141 -0.4862279   0.1029708 -0.6919154e-2;
               1.908368  -3.415721   2.124052  -0.4298159  0.02798384;
             -0.7957312  0.7187330 -0.9678804   0.2431675 -0.01644710;
             -0.9399577   2.314054 -0.4877045  0.03932058 -0.1600850e-2]
   )
