# This file is a part of BAT.jl, licensed under the MIT License (MIT).


struct CubaIntegrand{D<:AbstractDensity,T<:Real} <: Function
    density::D
    log_density_shift::T
    log_support_volume::T
end


function CubaIntegrand(density::AbstractDensity, log_density_shift::Real)
    vol = spatialvolume(var_bounds(density))
    isinf(vol) && throw(ArgumentError("CUBA integration doesn't support densities with infinite support"))
    log_support_volume = log_volume(vol)
    @assert _cuba_valid_value(log_support_volume)

    CubaIntegrand(density, float(log_density_shift), log_support_volume)
end


_cuba_valid_value(x) = !isnan(x) && x < typeof(x)(+Inf)


function (integrand::CubaIntegrand)(x::AbstractVector{<:Real}, f::AbstractVector{<:Real})
    idxs = axes(f, 1)
    @assert length(idxs) == 1

    vol = spatialvolume(var_bounds(integrand.density))
    x_trafo = fromuhc(x, vol)
    logd = eval_logval(integrand.density, x_trafo)
    @assert _cuba_valid_value(logd)

    f[first(idxs)] = exp(logd + integrand.log_density_shift)
    @assert all(_cuba_valid_value,f)

    f
end


function (integrand::CubaIntegrand)(X::AbstractMatrix{<:Real}, f::AbstractMatrix{<:Real})
    idxs1 = axes(f, 1)
    @assert length(idxs1) == 1
    idxs2 = axes(f, 2)
    @assert idxs2 == axes(X, 2)

    vol = spatialvolume(var_bounds(integrand.density))
    x_trafo = fromuhc(nestedview(X), vol)
    @threads for i in idxs2
        logd = eval_logval(integrand.density, x_trafo[i])
        @assert _cuba_valid_value(logd)
        y = exp(logd + integrand.log_density_shift)
        @assert _cuba_valid_value(y)
        f[first(idxs1), i] = y
    end

    f
end



"""
    VEGASIntegration

VEGASIntegration integration algorithm.

Only supports densities with finite rectangular bounds.

!!! note

    This functionality is only available then the
    [Cuba](https://github.com/giordano/Cuba.jl) package is loaded (e.g. via
    `import CUBA`).
"""
@with_kw struct VEGASIntegration{TR<:AbstractDensityTransformTarget} <: IntegrationAlgorithm
    trafo::TR = PriorToUniform()
    log_density_shift::Float64 = 0.0
    rtol::Float64 = Cuba.RTOL
    atol::Float64 = Cuba.ATOL
    minevals::Int = Cuba.MINEVALS
    maxevals::Int = Cuba.MAXEVALS
    nstart::Int = Cuba.NSTART
    nincrease::Int = Cuba.NINCREASE
    nbatch::Int = Cuba.NBATCH
    nthreads::Int = Base.Threads.nthreads()
end
export VEGASIntegration


function bat_integrate_impl(integrand::CubaIntegrand, algorithm::VEGASIntegration)
    r = Cuba.vegas(
        integrand, totalndof(integrand.density), 1, nvec = algorithm.nthreads,
        rtol = algorithm.rtol, atol = algorithm.atol,
        minevals = algorithm.minevals, maxevals = algorithm.maxevals,
        nstart = algorithm.nstart, nincrease = algorithm.nincrease, nbatch = algorithm.nbatch
    )
end



"""
    SuaveIntegration

    SuaveIntegration integration algorithm.

Only supports densities with finite rectangular bounds.

!!! note

    This functionality is only available then the
    [Cuba](https://github.com/giordano/Cuba.jl) package is loaded (e.g. via
    `import CUBA`).
"""
@with_kw struct SuaveIntegration{TR<:AbstractDensityTransformTarget} <: IntegrationAlgorithm
    trafo::TR = PriorToUniform()
    log_density_shift::Float64 = 0.0
    rtol::Float64 = Cuba.RTOL
    atol::Float64 = Cuba.ATOL
    minevals::Int = Cuba.MINEVALS
    maxevals::Int = Cuba.MAXEVALS
    nnew::Int = Cuba.NNEW
    nmin::Int = Cuba.NMIN
    flatness::Float64 = Cuba.FLATNESS
    nthreads::Int = Base.Threads.nthreads()
end
export SuaveIntegration


function bat_integrate_impl(integrand::CubaIntegrand, algorithm::SuaveIntegration)
    Cuba.suave(
        integrand, totalndof(integrand.density), 1, nvec = algorithm.nthreads,
        rtol = algorithm.rtol, atol = algorithm.atol,
        minevals = algorithm.minevals, maxevals = algorithm.maxevals,
        nnew = algorithm.nnew, nmin = algorithm.nmin, flatness = algorithm.flatness
    )
end



"""
    DivonneIntegration

    DivonneIntegration integration algorithm.

Only supports densities with finite rectangular bounds.

!!! note

    This functionality is only available then the
    [Cuba](https://github.com/giordano/Cuba.jl) package is loaded (e.g. via
    `import CUBA`).
"""
@with_kw struct DivonneIntegration{TR<:AbstractDensityTransformTarget} <: IntegrationAlgorithm
    trafo::TR = PriorToUniform()
    log_density_shift::Float64 = 0.0
    rtol::Float64 = Cuba.RTOL
    atol::Float64 = Cuba.ATOL
    minevals::Int = Cuba.MINEVALS
    maxevals::Int = Cuba.MAXEVALS
    key1::Int = Cuba.KEY1
    key2::Int = Cuba.KEY2
    key3::Int = Cuba.KEY3
    maxpass::Int = Cuba.MAXPASS
    border::Float64 = Cuba.BORDER
    maxchisq::Float64 = Cuba.MAXCHISQ
    mindeviation::Float64 = Cuba.MINDEVIATION
    ngiven::Int = Cuba.NGIVEN
    ldxgiven::Int = Cuba.LDXGIVEN
    nextra::Int = Cuba.NEXTRA
    nthreads::Int = Base.Threads.nthreads()
end
export DivonneIntegration


function bat_integrate_impl(integrand::CubaIntegrand, algorithm::DivonneIntegration)
    Cuba.divonne(
        integrand, totalndof(integrand.density), 1, nvec = algorithm.nthreads,
        rtol = algorithm.rtol, atol = algorithm.atol,
        minevals = algorithm.minevals, maxevals = algorithm.maxevals,
        key1 = algorithm.key1, key2 = algorithm.key2, key3 = algorithm.key3,
        maxpass = algorithm.maxpass, border = algorithm.border, maxchisq = algorithm.maxchisq,
        mindeviation = algorithm.mindeviation, ngiven = algorithm.ngiven, ldxgiven = algorithm.ldxgiven,
        nextra = algorithm.nextra
    )
end



"""
    CuhreIntegration

    CuhreIntegration integration algorithm.

Only supports densities with finite rectangular bounds.

!!! note

    This functionality is only available then the
    [Cuba](https://github.com/giordano/Cuba.jl) package is loaded (e.g. via
    `import CUBA`).
"""
@with_kw struct CuhreIntegration{TR<:AbstractDensityTransformTarget} <: IntegrationAlgorithm
    trafo::TR = PriorToUniform()
    log_density_shift::Float64 = 0.0
    rtol::Float64 = Cuba.RTOL
    atol::Float64 = Cuba.ATOL
    minevals::Int = Cuba.MINEVALS
    maxevals::Int = Cuba.MAXEVALS
    key::Int = Cuba.KEY
    nthreads::Int = Base.Threads.nthreads()
end
export CuhreIntegration


function bat_integrate_impl(integrand::CubaIntegrand, algorithm::CuhreIntegration)
    Cuba.cuhre(
        integrand, totalndof(integrand.density), 1, nvec = algorithm.nthreads,
        rtol = algorithm.rtol, atol = algorithm.atol,
        minevals = algorithm.minevals, maxevals = algorithm.maxevals,
        key = algorithm.key
    )
end



const CubaIntegration = Union{VEGASIntegration, SuaveIntegration, DivonneIntegration, CuhreIntegration}

function bat_integrate_impl(target::AnyDensityLike, algorithm::CubaIntegration)
    density_notrafo = convert(AbstractDensity, target)
    density, trafo = bat_transform(algorithm.trafo, density_notrafo)
    integrand = CubaIntegrand(density, algorithm.log_density_shift)

    r_cuba = bat_integrate_impl(integrand, algorithm)

    log_renorm_corr = -integrand.log_density_shift + integrand.log_support_volume
    T = promote_type(BigFloat, typeof(log_renorm_corr))
    renorm_corr = exp(convert(T, log_renorm_corr))

    ival = first(r_cuba.integral) * renorm_corr
    ierr = first(r_cuba.error) * renorm_corr

    (result = Measurements.measurement(ival, ierr), cuba_result = r_cuba, renorm_corr = renorm_corr)
end
