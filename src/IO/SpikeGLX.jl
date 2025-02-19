"""
Convert raw `Neuropixels` data to gain-corrected voltages. The saved-channel id subset in data
will be used to get corresponding gain.

The full conversion with gain is:

``dataVolts = dataInt * fi2v / gain``

Note that each channel may have its own gain.

1. y: the saved data stream, excluding the last Sync channel.
2. meta: corresponding meta for y
"""
function gaincorrectnp(y,meta)
    yt = meta["from"][1:2]
    fi2v = meta["fi2v"]
    gain = meta["ro$(yt)gain"]
    nch = length(gain)
    savechids = meta["savedchans"]
    chids = yt == "ap" ? filter!(i->i<=nch,savechids) : filter!(i->i>nch,savechids).-nch

    cy=Array{Float64}(undef,size(y))
    for i in 1:size(y,1)
        cy[i,:] = y[i,:] * fi2v / gain[chids[i]]
    end
    return cy
end

"Map linear channel index to probe shape indices"
function chshapenp(ch,nrow,ncol)
    r = ceil(Int,ch/ncol)
    c = ch-(r-1)*ncol
    return r,c
end
"""
Logical mask for `Neuropixels` channels in probe shape
     1 2
     3 4
     5 6
     ...
"""
function chmasknp(chs,nrow,ncol)
    mask = falses(ncol,nrow) # Neuropixel channel counting is from cols(left -> right), then rows(tip -> tail)
    mask[chs].=true
    permutedims(mask)
end
"Logical mask for `Neuropixels` reference channels in probe shape"
function refchmasknp(dataset;imecindex="0")
    refch = dataset["ap$imecindex"]["meta"]["refch"]
    chmasknp(refch,dataset["ap$imecindex"]["meta"]["nrowsaved"],dataset["ap$imecindex"]["meta"]["ncolsaved"])
end
"Logical mask for `Neuropixels` excluded channels in probe shape"
function exchmasknp(dataset;imecindex="0",datatype="lf",exch::Vector{Int}=Int[])
    exchs = dataset[datatype]["meta"]["excludechans"]
    chmasknp(union(exchs,exch),dataset["ap$imecindex"]["meta"]["nrowsaved"],dataset["ap$imecindex"]["meta"]["ncolsaved"])
end
