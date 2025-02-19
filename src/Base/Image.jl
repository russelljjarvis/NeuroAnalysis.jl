alphablend(fg,bg,ff,bf=1-ff) = ff.*fg .+ bf.*bg
"alpha weighted average of foreground and background colors"
function alphablend(fg::Colorant,bg::Colorant)
    a = alpha(fg)
    a*color(fg) + (1-a)*color(bg)
end

function alphamask(img;color=:bwr,radius=0.5,sigma=0.35,masktype="Gaussian")
    cg = cgrad(color)
    m = maximum(abs.(img))
    alphamask(get(cg,img,(-m,m));radius,sigma,masktype)[1]
end
"""
Masking alpha channel of an image, match the implementation in `Experica` shaders.
"""
function alphamask(src::Matrix{<:Colorant};radius=0.5,sigma=0.15,masktype="Disk")
    if masktype in ["Disk","disc"]
        alphamask_disk(src,radius)
    elseif masktype=="Gaussian"
        alphamask_gaussian(src,sigma)
    elseif masktype=="DiskFade"
        alphamask_diskfade(src,radius,sigma)
    else
        return (y=coloralpha.(src),i=Int[])
    end
end
function alphamask_disk(src,radius)
    dims = size(src);hh,hw = dims./2;id=minimum(dims)
    dst = coloralpha.(src);unmaskidx=Int[];li = LinearIndices(dims)
    for i=1:dims[1],j=1:dims[2]
        d = sqrt((i-hh)^2+(j-hw)^2)/id-radius
        if d>0
            dst[i,j]=coloralpha(color(dst[i,j]),0)
        else
            push!(unmaskidx,li[i,j])
        end
    end
    return (y=dst,i=unmaskidx)
end
function alphamask_gaussian(src,sigma)
    dims = size(src);hh,hw = dims./2;ir=min(hh,hw)
    dst = coloralpha.(src);unmaskidx=Int[];li = LinearIndices(dims)
    for i=1:dims[1],j=1:dims[2]
        r2 = ((i-hh)^2+(j-hw)^2)/ir^2
        dst[i,j]=coloralpha(color(dst[i,j]),alpha(dst[i,j])*exp(-0.5r2/sigma^2))
        push!(unmaskidx,li[i,j])
    end
    return (y=dst,i=unmaskidx)
end
function alphamask_diskfade(src,radius,sigma)
    dims = size(src);hh,hw = dims./2;id=minimum(dims)
    dst = coloralpha.(src);unmaskidx=Int[];li = LinearIndices(dims)
    for i=1:dims[1],j=1:dims[2]
        d = sqrt((i-hh)^2+(j-hw)^2)/id-radius
        if d>0
            dst[i,j] = coloralpha(color(dst[i,j]),alpha(dst[i,j])*erfc(sigma*d))
        else
            push!(unmaskidx,li[i,j])
        end
    end
    return (y=dst,i=unmaskidx)
end

"clamp value to `min` and `max`, and linearly map range `[min, max]` to `[0, 1]`"
function clampscale(x,min::Real,max::Real)
    scaleminmax(min,max).(x)
end
clampscale(x) = clampscale(x,extrema(x)...)
function clampscale(x,sdfactor)
    m=mean(x);sd=std(x)
    clampscale(x,m-sdfactor*sd,m+sdfactor*sd)
end
function oiframeresponse(frames;frameindex=nothing,baseframeindex=nothing)
    if frameindex==nothing
        r = dropdims(sum(frames,dims=3),dims=3)
    else
        r = dropdims(sum(frames[:,:,frameindex],dims=3),dims=3)
    end
    if baseframeindex!=nothing
        r./=dropdims(sum(frames[:,:,baseframeindex],dims=3),dims=3)
        r.-=1
    end
    return r
end
"""
Frame Response, (R - R₀) / R₀
"""
function frameresponse(frames;frameindex=1:size(frames,3),baseframeindex=[],reducefun=mean)
    @views r = dropdims(reducefun(frames[:,:,frameindex],dims=3),dims=3)
    if !isempty(baseframeindex)
        @views b = dropdims(reducefun(frames[:,:,baseframeindex],dims=3),dims=3)
        return r ./ b .- 1
    end
    return r
end
function oiresponse(response,stimuli;ustimuli=sort(unique(stimuli)),blankstimuli=0,
    stimuligroup=Any[1:length(findall(ustimuli.!=blankstimuli))],filter=nothing,sdfactor=nothing)
    if filter==nothing
        if sdfactor==nothing
            rs = map(i->cat(response[stimuli.==i]...,dims=3),ustimuli)
        else
            rs = map(i->cat(clampscale.(response[stimuli.==i],sdfactor)...,dims=3),ustimuli)
        end
    else
        if sdfactor==nothing
            rs = map(i->cat(imfilter.(response[stimuli.==i],[filter])...,dims=3),ustimuli)
        else
            rs = map(i->cat(clampscale.(imfilter.(response[stimuli.==i],[filter]),sdfactor)...,dims=3),ustimuli)
        end
    end
    responsemean = map(i->dropdims(mean(i,dims=3),dims=3),rs)
    responsesd = map(i->dropdims(std(i,dims=3),dims=3),rs)
    responsen = map(i->size(i,3),rs)

    blank = responsemean[findfirst(ustimuli.==blankstimuli)]
    rindex = ustimuli.!=blankstimuli
    rmap=responsemean[rindex]
    cocktail=Any[];cocktailmap=Any[]
    for ig in stimuligroup
        c = dropdims(mean(cat(rmap[ig]...,dims=3),dims=3),dims=3)
        cm = map(i->i./c,rmap[ig])
        push!(cocktail,c)
        append!(cocktailmap,cm)
    end
    return blank,cocktail,DataFrame(stimuli=ustimuli[rindex],map=rmap,blankmap=map(i->i./blank,rmap),cocktailmap=cocktailmap),
    DataFrame(stimuli=ustimuli,map=responsemean,mapsd=responsesd,mapn=responsen)
end
function oicomplexmap(maps,angles;isangledegree=true,isangleinpi=true,presdfactor=3,filter=Kernel.DoG((3,3),(30,30)),sufsdfactor=3)
    if isangledegree
        angledegree = sort(angles)
        angles = deg2rad.(angles)
    else
        angledegree = sort(rad2deg.(angles))
    end
    if isangleinpi
        angles *=2
    end
    if presdfactor!=nothing
        maps=map(i->clampscale(i,presdfactor),maps)
    end
    if filter != nothing
        maps=map(i->imfilter(i,filter),maps)
    end
    if sufsdfactor!=nothing
        maps=map(i->clampscale(i,sufsdfactor),maps)
    end

    cmap=dropdims(sum(cat(map((m,a)->Complex(cos(a),sin(a)).*-m,maps,angles)...,dims=3),dims=3),dims=3)
    amap,mmap = angleabs(cmap)
    return Dict("complex"=>cmap,"angle"=>amap,"abs"=>mmap,"rad"=>sort(angles),"deg"=>angledegree)
end
"""
Complex sum of angles and corresponding image responses

1. image responses [height, width, n]
2. angles in radius [n]

- centerfun: function to get center for sdfactor (median)
- presdfactor: center +- sdfactor * sd, for clamping before filtering
- filter: filter kernel
- sufsdfactor: center +- sdfactor * sd, for clamping after filtering
- responsesign: increasing/decreasing(+/-) response

return complex map, angle map, and magnitude map
"""
function complexmap(maps,angles;centerfun=median,presdfactor=3,filter=Kernel.DoG((3,3,0)),sufsdfactor=3,responsesign=-1)
    if !isnothing(presdfactor)
        c = centerfun(maps,dims=(1,2));sd = std(maps,dims=(1,2))
        maps = clamp.(maps,c.-presdfactor.*sd,c.+presdfactor.*sd)
    end
    if !isnothing(filter)
        # remove high/low freq artifacts [~2mm, ~0.1mm]
        maps = imfilter(maps,filter)
    end
    if !isnothing(sufsdfactor)
        c = centerfun(maps,dims=(1,2));sd = std(maps,dims=(1,2))
        maps = clamp.(maps,c.-sufsdfactor.*sd,c.+sufsdfactor.*sd)
    end
    maps = sign(responsesign)*maps
    maps .-= minimum(maps)
    cmap = dropdims(sum(maps .* reshape(exp.(im*angles),1,1,:),dims=3),dims=3)
    amap = mod2pi.(angle.(cmap) .+ 2π)
    mmap = abs.(cmap)
    rad = sort(angles)
    deg = rad2deg.(rad)
    return (;cmap,amap,mmap,rad,deg)
end

function angleabs(cmap)
    amap = angle.(cmap);amap[amap.<0]=amap[amap.<0] .+ 2pi
    mmap = clampscale(abs.(cmap))
    return amap,mmap
end
anglemode(a,theta) = theta[findclosestangle(a,theta)]
"find closest distance and index in α to β, all in radius"
function findclosestangle(α,β)
    m,i=findmin(abs.(circ_dist2(α,β)),dims=1)
    length(m) == 1 ? (m[1],i[1]) : (vec(m),map(i->i[1],vec(i)))
end

"""
Generate Grating Image, match the implementation in `Experica` grating shader.

- θ: Orientation (radius), 0 is -, increase counter-clock wise
- sf: SpatialFreq (cycle/deg)
- tf: TemporalFreq (cycle/sec)
- t: Time (second)
- phase: Phase of a cycle in [0, 1] scale
- size: Tuple of image size in degree
- ppd: pixel per degree
- isnorm: return image in [0, 1] or [-1, 1]

"""
function grating(;θ=0,sf=1,phase=0,tf=1,t=0,size=(10,10),ppd=50,isnorm=true)
    pr = round.(Int,size.*ppd./2);pc = pr.+1;psize = (pr.*2).+1
    g = zeros(psize)
    if !isnan(θ)
        sinθ,cosθ = sincos(θ)
        for i in 1:psize[1], j in 1:psize[2]
            x = (j-pc[2])/pr[2]/2
            y = (-i+pc[1])/pr[1]/2
            y′ = cosθ * y * size[1] - sinθ * x * size[2]
            g[i,j] = sin(2π * (sf * y′ - tf * t + phase))
        end
    end
    isnorm && (g=(g.+1)/2)
    return g
end

"""
Generate Hartley Subspace, where k is frequency in cycle/unit_x/y. [^1]

- kbegin: k >= kbegin
- kend: k <= kend
- dk: Δk, step on k axis
- phase: phase in [0, 1] scale, default 0.
- shape: `:square` or `:circle` shape subspace
- addhalfcycle: add half cycle shifted hartleys
- blank: the element of hartley as blank, default uniform gray.
- nblank: number of blanks to add

[^1]

Ringach, D.L., Sapiro, G., and Shapley, R. (1997). A subspace reverse-correlation technique for the study of visual neurons. Vision Research 37, 2455–2464.
"""
function hartleysubspace(;kbegin=0.0,kend=5.0,dk=1.0,phase=0.0,shape=:square,addhalfcycle=false,blank=(kx=0.0,ky=0.0,phase=0.375),nblank=0)
    kr = 0:dk:kend; kaxis = sort(unique([kr;-kr]))
    ps = vec([(kx=kx,ky=ky,phase=phase) for ky in reverse(kaxis), kx in kaxis])
    if shape == :square
        if 0 < kbegin
            filter!(i->abs(i.kx) >= kbegin || abs(i.ky) >= kbegin,ps)
        end
    elseif shape == :circle
        filter!(i->kbegin <= sqrt(i.kx^2 + i.ky^2) <= kend,ps)
    end
    if addhalfcycle
        append!(ps,map(i->(kx=i.kx,ky=i.ky,phase=i.phase + 0.5),ps))
    end
    if nblank > 0
        append!(ps,fill(blank,nblank))
    end
    ps
end

"""
Generate gratings in Hartley space (PL)
- kx, ky: wavenumber along x, y axis
- bw: black and white (phase) flip
- stisize: stimulus size in visual angle (degree); note that sz[1]=sz[2]
if norm=true,Return image in [0,1], otherwise return image in [-1,1]
"""
function hartley(; kx,ky,bw,stisize=5,ppd=50,norm=false,scale=1)
    sz = round.(Int,stisize.*ppd./2).*2
    vect=collect(0:sz-1)
    nxmat = repeat(vect',sz,1)
    nymat = repeat(vect,1,sz)
    kxy = 2π .* (kx .* nxmat + ky .* nymat) ./ sz
    g = (sin.(kxy) + cos.(kxy)) ./ sqrt(2)
    if norm == true
        g = (g .* bw ./ max(g...) .+ 1) ./ 2 .*scale
    elseif norm == false
        g = g .* bw ./ max(g...) .* scale
    end
    return g
end

"""
2D powerspectrum of an image.
"""
function powerspectrum2(x::Matrix,fs;freqrange=[-15,15])
    ps = periodogram(x,fs=fs)
    p = power(ps);freqd1,freqd2 = freq(ps)
    fi1 = freqrange[1].<=freqd1.<=freqrange[2]
    fi2 = freqrange[1].<=freqd2.<=freqrange[2]
    p = p[fi1,fi2];freqd1 = freqd1[fi1];freqd2 = freqd2[fi2]
    si1=sortperm(freqd1);si2=sortperm(freqd2)
    return p[si1,si2],freqd1[si1],freqd2[si2]
end

"2D powerspectrums of images in same size."
function powerspectrums2(xs::Vector,fs;freqrange=[-15,15])
    pss=[]
    ps,f1,f2 = powerspectrum2(xs[1],fs;freqrange)
    push!(pss,ps)
    for i in 2:length(xs)
        push!(pss,powerspectrum2(xs[i],fs;freqrange)[1])
    end
    return pss,f1,f2
end

"""
Estimate the F1 Ori and SpatialFreq of an image from its 2D powerspectrum.

1. x: 2D powerspectrum
2. freqd1: frequencies of dim 1
3. freqd2: frequencies of dim 2

return:
- ori: Orientation in radius, 0 is -, increase counter-clock wise
- sf: SpatialFreq along the line perpendicular to ori
"""
function f1orisf(x,freqd1,freqd2)
    f0i = (findfirst(freqd1.==0),findfirst(freqd2.==0))
    p = deepcopy(x);p[f0i...]=0
    f1i = argmax(p)
    f1freqd2d1 = [freqd2[f1i[2]],freqd1[f1i[1]]]
    ori = mod(atan(f1freqd2d1...),π)
    sf = norm(f1freqd2d1)
    return ori,sf
end

"extrema value of max amplitude and it's delay index"
function exd(sta)
    exi = [argmin(sta),argmax(sta)]
    ex = sta[exi]
    absexi = argmax(abs.(ex))
    (ex=ex[absexi],d=ndims(sta) > 2 ? exi[absexi][3] : missing)
end
"""
local RMS contrast of each image, highlighting local structure regions
"""
function localcontrast(csta,w::Integer)
    dims = size(csta)
    clc = Array{Float64}(undef,dims)
    w = iseven(w) ? w+1 : w
    @views for d in 1:dims[3], c in 1:dims[4]
        clc[:,:,d,c] = mapwindow(std,csta[:,:,d,c],(w,w))
    end
    return clc
end
function localcontrast(data::Matrix,w::Integer)
    w = iseven(w) ? w+1 : w
    mapwindow(std,data,(w,w))
end
"ROI encompass peak value and its delay index"
function peakroi(clc)
    ds = size(clc)[1:2]
    i = [Tuple(argmax(clc))...]
    plc = clc[:,:,i[3:end]...]
    return (peakroi(plc,ds=ds,i=i[1:2])...,pdi=i[3])
end
function peakroi(data::Matrix;ds = size(data),i = [Tuple(argmax(data))...])
    segs = seeded_region_growing(data,[(CartesianIndex(1,1),1),(CartesianIndex(1,ds[2]),1),(CartesianIndex(ds[1],1),1),
                            (CartesianIndex(ds...),1),(CartesianIndex(i...),2)])
    idx = findall(labels_map(segs).==2)
    roi = roiwindow(idx)
    return (i=idx,center=roi.center,radius=round(Int,maximum(roi.hw)/2))
end
"Get ROI from region indices"
function roiwindow(idx)
    idxlims = dropdims(extrema(mapreduce(i->[Tuple(i)...],hcat,idx),dims=2),dims=2)
    hw = map(i->i[2]-i[1],idxlims)
    center = round.(Int,mean.(idxlims))
    return (;center,hw)
end
"Get the minimum ROI region encompass all rois"
function mergeroi(rois,ds;roimargin=0)
    cs = mapfoldl(r->r.center,hcat,rois,init=zeros(Int,2,0))
    center = round.(Int,vec(mean(cs,dims=2)))
    cdev = maximum(Distances.colwise(Euclidean(),cs,center))
    radius = round(Int,(maximum(r->r.radius,rois)+cdev)*(1+roimargin))
    radius = clamproi(center,radius,ds)
    return (;center,radius)
end
"Confine ROI radius so that ROI is within the image"
function clamproi(center,radius,ds)
    vr = map(i->intersect(center[i].+(-radius:radius),1:ds[i]),1:2)
    radius = (minimum ∘ mapreduce)((r,c)->abs.([r[begin],r[end]].-c),append!,vr,center)
end

function imresize_antialiasing(img,sz)
    isz = size(img)
    iisz = isz[1:2]
    iisz == sz && return img
    if any(sz .< iisz)
        σ = (map((o,n)->0.2*o/n, iisz, sz)...,zeros(length(isz)-2)...)
        return imresize(imfilter(img, KernelFactors.gaussian(σ), NA()), sz)
    else
        return imresize(img, sz)
    end
end
