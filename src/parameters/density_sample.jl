# This file is a part of BAT.jl, licensed under the MIT License (MIT).


const _default_float_WT = Float64 # Default type for float weights
const _default_int_WT = Int # Default type for int weights
const _default_LDT = Float64 # Default type for log-density values


"""
    struct DensitySample

A weighted sample drawn according to an statistical density,
e.g. a [`BAT.AbstractDensity`](@ref).

Fields:
    * `v`: Multivariate parameter vector
    * `logd`: log of the value of the density at `v`
    * `weight`: Weight of the sample
    * `info`: Additional info on the provenance of the sample. Content depends
       on the sampling algorithm.
    * aux: Custom user-defined information attatched to the sample.

Constructors:

```julia
DensitySample(
    v::AbstractVector{<:Real},
    logd::Real,
    weight::Real,
    info::Any,
    aux::Any
)
```

Use [`DensitySampleVector`](@ref) to store vectors of multiple samples with
an efficient column-based memory layout.
"""
struct DensitySample{
    P,
    T<:Real,
    W<:Real,
    R,
    Q
}
    v::P
    logd::T
    weight::W
    info::R
    aux::Q
end

export DensitySample


# DensitySample behaves as a scalar type under broadcasting:
@inline Base.Broadcast.broadcastable(shape::DensitySample) = Ref(shape)


import Base.==
function ==(A::DensitySample, B::DensitySample)
    A.v == B.v && A.logd == B.logd &&
        A.weight == B.weight && A.info == B.info && A.aux == B.aux
end


function Base.similar(s::DensitySample{P,T,W,R,Q}) where {P<:AbstractVector{<:Real},T,W,R,Q}
    v = fill!(similar(s.v), oob(eltype(s.v)))
    logd = convert(T, NaN)
    weight = zero(W)
    info = R()
    aux = Q()
    P_new = typeof(v)
    DensitySample{P_new,T,W,R,Q}(v, logd, weight, info, aux)
end


function _apply_shape(shape::AbstractValueShape, s::DensitySample)
    DensitySample(
        stripscalar(shape(s.v)),
        s.logd,
        s.weight,
        s.info,
        s.aux,
    )
end

@static if VERSION >= v"1.3"
    (shape::AbstractValueShape)(s::DensitySample) = _apply_shape(shape, s)
else
    (shape::ScalarShape)(s::DensitySample) = _apply_shape(shape, s)
    (shape::ArrayShape)(s::DensitySample) = _apply_shape(shape, s)
    (shape::ConstValueShape)(s::DensitySample) = _apply_shape(shape, s)
    (shape::NamedTupleShape)(s::DensitySample) = _apply_shape(shape, s)
end



"""
    DensitySampleVector

Type alias for `StructArrays.StructArray{<:DensitySample,...}`.

Constructor:

```julia
    DensitySampleVector(
        (
            v::AbstractVector{<:AbstractVector{<:Real}}
            logd::AbstractVector{<:Real}
            weight::AbstractVector{<:Real}
            info::AbstractVector{<:Any}
            aux::AbstractVector{<:Any}
        )
    )
```
"""
const DensitySampleVector{
    P,T<:AbstractFloat,W<:Real,R,Q,
    PV<:AbstractVector{P},TV<:AbstractVector{T},WV<:AbstractVector{W},RV<:AbstractVector{R},QV<:AbstractVector{Q}
} = StructArray{
    DensitySample{P,T,W,R,Q},
    1,
    NamedTuple{(:v, :logd, :weight, :info, :aux), Tuple{PV,TV,WV,RV,QV}}
}

export DensitySampleVector


function StructArray{DensitySample}(
    contents::Tuple{
        AbstractVector{P},
        AbstractVector{T},
        AbstractVector{W},
        AbstractVector{R},
        AbstractVector{Q},
    }
) where {P,T<:AbstractFloat,W<:Real,R,Q}
    v, logd, weight, info, aux = contents
    StructArray{DensitySample{P,T,W,R,Q}}(contents)
end


DensitySampleVector(contents::NTuple{5,Any}) = StructArray{DensitySample}(contents)


_create_undef_vector(::Type{T}, len::Integer) where T = Vector{T}(undef, len)


function DensitySampleVector{P,T,W,R,Q}(::UndefInitializer, len::Integer, npar::Integer) where {
    PT<:Real, P<:AbstractVector{PT}, T<:AbstractFloat, W<:Real, R, Q
}
    contents = (
        VectorOfSimilarVectors(ElasticArray{PT}(undef, npar, len)),
        Vector{T}(undef, len),
        Vector{W}(undef, len),
        _create_undef_vector(R, len),
        _create_undef_vector(Q, len)
    )

    DensitySampleVector(contents)
end

DensitySampleVector(::Type{S}, varlen::Integer) where {P<:AbstractVector{<:Real},T<:AbstractFloat,W<:Real,R,Q,S<:DensitySample{P,T,W,R,Q}} =
    DensitySampleVector{P,T,W,R,Q}(undef, 0, varlen)


# Specialize getindex to properly support ArraysOfArrays, preventing
# conversion to exact element type:
@inline Base.getindex(A::StructArray{<:DensitySample}, I::Int...) =
    DensitySample(A.v[I...], A.logd[I...], A.weight[I...], A.info[I...], A.aux[I...])

# Specialize IndexStyle, current default for StructArray seems to be IndexCartesian()
Base.IndexStyle(::StructArray{<:DensitySample, 1}) = IndexLinear()

# Specialize comparison, currently StructArray seems fall back to `(==)(A::AbstractArray, B::AbstractArray)`
import Base.==
function(==)(A::DensitySampleVector, B::DensitySampleVector)
    A.v == B.v &&
    A.logd == B.logd &&
    A.weight == B.weight &&
    A.info == B.info &&
    A.aux == B.aux
end


function Base.merge!(X::DensitySampleVector, Xs::DensitySampleVector...)
    for Y in Xs
        append!(X, Y)
    end
    X
end

Base.merge(X::DensitySampleVector, Xs::DensitySampleVector...) = merge!(deepcopy(X), Xs...)


function UnsafeArrays.uview(A::DensitySampleVector)
    DensitySampleVector((
        uview(A.v),
        uview(A.logd),
        uview(A.weight),
        uview(A.info),
        uview(A.aux)
    ))
end


Base.@propagate_inbounds function _bcasted_apply_to_params(f, A::DensitySampleVector)
    DensitySampleVector((
        f.(A.v),
        A.logd,
        A.weight,
        A.info,
        A.aux
    ))
end

Base.copy(
    instance::Base.Broadcast.Broadcasted{
        <:Base.Broadcast.AbstractArrayStyle{1},
        <:Any,
        <:Union{AbstractValueShape,typeof(unshaped)},
        <:Tuple{DensitySampleVector}
    }
) = _bcasted_apply_to_params(instance.f, instance.args[1])


ValueShapes.varshape(A::DensitySampleVector) = elshape(A.v)


Statistics.mean(samples::DensitySampleVector) = mean(samples.v, FrequencyWeights(samples.weight))
Statistics.var(samples::DensitySampleVector) = var(samples.v, FrequencyWeights(samples.weight))
Statistics.std(samples::DensitySampleVector) = sqrt.(var(samples))
Statistics.cov(samples::DensitySampleVector) = cov(samples.v, FrequencyWeights(samples.weight))
Statistics.cor(samples::DensitySampleVector) = cor(samples.v, FrequencyWeights(samples.weight))

function _get_mode(samples::DensitySampleVector)
    i = findmax(samples.logd)[2]
    v = samples.v[i]

    (v, i)
end


StatsBase.mode(samples::DensitySampleVector) = _get_mode(samples)[1]


"""
    drop_low_weight_samples(
        samples::DensitySampleVector,
        fraction::Real = 10^-4
    )

*BAT-internal, not part of stable public API.*

Drop `fraction` of the total probability mass from samples to filter out the
samples with the lowest weight.
"""
function drop_low_weight_samples(samples::DensitySampleVector, fraction::Real = 10^-5)
    W = float(samples.weight)
    if minimum(W) / maximum(W) > 10^-2
        samples
    else
        W_s = sort(W)
        Q = cumsum(W_s)
        Q ./= maximum(Q)
        @assert last(Q) ≈ 1
        thresh = W_s[searchsortedlast(Q, fraction)]
        idxs = findall(x -> x >= thresh, samples.weight)
        samples[idxs]
    end
end
