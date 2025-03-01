struct BACKSAFTParam <: EoSParam
    segment::SingleParam{Float64}
    sigma::PairParam{Float64}
    epsilon::PairParam{Float64}
    c::SingleParam{Float64}
    alpha::SingleParam{Float64}
end

abstract type BACKSAFTModel <: SAFTModel end
@newmodel BACKSAFT BACKSAFTModel BACKSAFTParam

export BACKSAFT
function BACKSAFT(components::Array{String,1}; idealmodel=BasicIdeal, userlocations::Array{String,1}=String[], verbose=false)
    params = getparams(components, ["SAFT/BACKSAFT","properties/molarmass.csv"]; userlocations=userlocations, verbose=verbose)
    segment = params["m"]
    c = params["c"]
    k = params["k"]
    alpha = params["alpha"]
    sigma = params["vol"]
    sigma.values .*= 6/N_A/1e6/π
    sigma.values .^= 1/3
    sigma = sigma_LorentzBerthelot(sigma)
    epsilon = epsilon_LorentzBerthelot(params["epsilon"], k)
    packagedparams = BACKSAFTParam(segment, sigma, epsilon, c, alpha)
    references = ["TODO BACKSAFT", "TODO BACKSAFT"]

    model = BACKSAFT(packagedparams, idealmodel; references=references, verbose=verbose)
    return model
end

function a_res(model::BACKSAFTModel ,V, T, z)
    a_hcb_ = @f(a_hcb)
    a_disp_ = @f(a_disp)
    a_chain_ = @f(a_chain)
    return  a_hcb_ + a_chain_ + (1.75*(a_chain_/a_hcb_)+1)*a_disp_
end

function a_hcb(model::BACKSAFTModel, V, T, z)
    α = model.params.alpha.values[1]
    m = model.params.segment.values[1]
    η = @f(ζ,3)
    return m*(α^2/(1-η)^2-(α^2-3α)/(1-η)-(1-α^2)*log(1-η)-3α)
end

function a_disp(model::BACKSAFTModel, V, T, z)
    m = model.params.segment.values[1]
    c = model.params.c.values[1]
    u = model.params.epsilon.values[1]*(1+c/T)
    η = @f(ζ,3)
    τ = 0.74048
    D1 = BACKSAFT_consts.D1
    D2 = BACKSAFT_consts.D2
    D3 = BACKSAFT_consts.D3
    D4 = BACKSAFT_consts.D4
    A1 = ∑(D1[j]*(u/T)*(η/τ)^j for j ∈ 1:6)
    A2 = ∑(D2[j]*(u/T)^2*(η/τ)^j for j ∈ 1:9)
    A3 = ∑(D3[j]*(u/T)^3*(η/τ)^j for j ∈ 1:5)
    A4 = ∑(D4[j]*(u/T)^4*(η/τ)^j for j ∈ 1:4)
    return m*(A1+A2+A3+A4)
end

function d(model::BACKSAFTModel, V, T, z, i)
    ϵ = model.params.epsilon.diagvalues
    σ = model.params.sigma.diagvalues
    return σ[i] * (1 - 0.12exp(-3ϵ[i]/T))
end

function ζ(model::BACKSAFTModel, V, T, z, n)
    ∑z = ∑(z)
    x = z/∑z
    m = model.params.segment.values
    return N_A*∑z*π/6/V * ∑(x[i]*m[i]*@f(d,i)^n for i ∈ @comps)
end

function a_chain(model::BACKSAFTModel, V, T, z)
    m = model.params.segment.values[1]
    return (1-m)*log(@f(g_hcb))
end

function g_hcb(model::BACKSAFTModel, V, T, z)
    α = model.params.alpha.values[1]
    η = @f(ζ,3)
    return 1/(1-η)+3*(1+α)*α*η/((1-η)^2*(1+3α))+3*η^2*α^2/((1-η)^3*(1+3α))
end

const BACKSAFT_consts = (
    D1 = [-8.8043,4.164627,-48.203555,140.4362,-195.23339,113.515],
    D2 = [2.9396,-6.0865383,40.137956,-76.230797,-133.70055,860.25349,-1535.3224,1221.4261,-409.10539],
    D3 = [-2.8225,4.7600148,11.257177,-66.382743,69.248785],
    D4 = [0.34,-3.1875014,12.231796,-12.110681],
)
