
"""
    rms(x,y)

Root mean square difference between `x` and `y`
"""
rms(x,y) = sqrt(mean((x - y).^2))


"""
    crms(x,y)

Centred root mean square difference between `x` and `y`
"""
crms(x,y) = rms(x .- mean(x),y .- mean(y))

bias(x,y) = mean(x) - mean(y)


function loadbatch(case,fname)
    ds = Dataset(fname);
    lon = ds["lon"][:]
    lat = ds["lat"][:]

    # all data
    ntest = ds.dim["time"]

    if haskey(case,:ntest)
        if get(case,:ntest,"") == "last-50"
            ntest = 50
        end
    end

    @show ntest

    mean_varname = case.varname
    sigma_varname = case.varname * "_error"

    batch_m_rec = ds[mean_varname][:,:,end-ntest+1:end]

    batch_sigma_rec =
        if sigma_varname != nothing
            ds[sigma_varname][:,:,end-ntest+1:end]
        else
            @warn "no error estimate found"
            zeros(size(batch_m_rec))
        end


    # add mean
    if haskey(ds,"batch_m_rec")
        # old files
        meandata = ds["meandata"][:]
        batch_m_rec = batch_m_rec .+ meandata
    end

    close(ds)

    ntest = size(batch_m_rec,3)

    ds = Dataset(case.fname_cv);
    batch_m_in = ds[case.varname][:,:,end-ntest+1:end]
    mask = ds["mask"][:];
    close(ds)

    ds = Dataset(case.fname_orig);
    batch_m_true = ds[case.varname][:,:,end-ntest+1:end]
    close(ds)

    return lon,lat,batch_m_true,batch_m_in,batch_m_rec,batch_sigma_rec,mask
end


function summary(case,fname;
                 fnamesummary = replace(fname,".nc" => "-" * case.varname * ".json")
)
    if isfile(fnamesummary)
    #if false
        summary = JSON.parse(read(fnamesummary,String))
        return summary
    else
        lon,lat,batch_m_true,batch_m_in,batch_m_rec,batch_sigma_rec,mask = loadbatch(case,fname)
        @show size(batch_m_true)
        mm = ismissing.(batch_m_in) .& .!ismissing.(batch_m_true) .& reshape(mask .== 1,(size(mask,1),size(mask,2),1));
        #mm = ismissing.(batch_m_in) .& .!ismissing.(batch_m_true)
        m_true = batch_m_true[mm]
        m_rec = batch_m_rec[mm]
        sigma_rec = batch_sigma_rec[mm];
        rms = sqrt(mean((m_true - m_rec).^2))
        bias = mean(m_true - m_rec)

        diff = abs.(m_true-m_rec);
        min_diff = minimum(diff)
        max_diff = maximum(diff)
        q10_diff,q90_diff = quantile(diff,(0.1,0.9))

        summary = Dict(
            "cvrms" => rms,
            "cvbias" => bias,
            "std_true" => std(m_true),
            "std_rec" => std(m_rec),
            "cor" => cor(m_true,m_rec),
            "cvcrms" => crms(m_true,m_rec),
            "number" => sum(mm),
            "min_diff" => min_diff,
            "max_diff" => max_diff,
            "q10_diff" => q10_diff,
            "q90_diff" => q90_diff,
        )

        for i = 1:3
            summary["$i-sigma"] = mean(abs.(m_true-m_rec) .<  i*sigma_rec)
        end

        open(fnamesummary,"w") do f
            JSON.print(f, summary)
        end
        return summary
    end
end

cvrms(case,fname; kwargs...) = Float32(summary(case,fname; kwargs...)["cvrms"])

function errstat(io,case,fname::AbstractString; figprefix = replace(fname,".nc" => ""))
    println(io,fname)

    lon,lat,batch_m_true,batch_m_in,batch_m_rec,batch_sigma_rec,mask = loadbatch(case,fname)

    errstat(io,case,batch_m_true,batch_m_in,batch_m_rec,batch_sigma_rec,figprefix)
end

function errstat(io,case,batch_m_true,batch_m_in,batch_m_rec,batch_sigma_rec,figprefix)
    diff = abs.(batch_m_true-batch_m_rec);


    # all
    #mm = .!(ismissing.(diff) .| ismissing.(batch_sigma_rec));
    # only CV
    mm = ismissing.(batch_m_in) .& .!ismissing.(batch_m_true)
    mm = ismissing.(batch_m_in) .& .!ismissing.(batch_m_true) .& .!ismissing.(batch_m_rec)
    println(io,"only CV points")

    m_true = batch_m_true[mm]
    m_rec = batch_m_rec[mm];
    sigma_rec = batch_sigma_rec[mm];

    println(io,"Number of CV points ",sum(mm))
    println(io,"Number of total data points ",sum(.!ismissing.(batch_m_true)))
    println(io,"RMS ",sqrt(mean((m_true - m_rec).^2)))

    for i = 1:3
        println(io,"$i-sigma: ",mean(abs.(m_true-m_rec) .<  i*sigma_rec),"  ",2*cdf(Normal(),i)-1)
    end

    x = (m_true-m_rec) ./ sigma_rec;

    if false
        clf()
        scatter(m_true,m_rec,10,sigma_rec; cmap = "jet")
        datarange = (min(minimum(m_true),minimum(m_rec)), max(maximum(m_true),maximum(m_rec)))
        xlim(datarange)
        ylim(datarange)
        plot([datarange[1],datarange[end]],[datarange[1],datarange[end]],"k--")
        xlabel("true $(case.varname)")
        ylabel("reconstructed $(case.varname)")
        axis("equal")
        colorbar()
        savefig(figprefix * "-scatter-err.png",dpi=300)
    end

    if true
        clf();
        pp = -10:0.1:10
        PyPlot.plt.hist(x,100, density = true, label = "scaled errors")
        plot(pp,pdf.(Normal(0,1),pp), label = "Normal distribution")
        xlim(pp[1],pp[end])
        ylim(0,0.5)
        legend()
        savefig(figprefix * "-pdf-err.png",dpi=300)
        savefig(figprefix * "-pdf-err.png")
        @show fit(Normal, x)
    end

end
