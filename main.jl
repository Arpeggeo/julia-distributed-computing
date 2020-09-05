using Distributed

# instantiate environment in all processes
@everywhere begin
  using Pkg; Pkg.activate(@__DIR__); Pkg.instantiate()
end

# load dependencies and helper functions
@everywhere begin
  using CSV

  function process(infile, outfile)
    # read file from disk
    csv = CSV.read(infile)

    # perform calculations
    sleep(60) # pretend it takes time
    csv.new = rand(size(csv,1))

    # save new file to disk
    CSV.write(outfile, csv)
  end
end

# MAIN SCRIPT
# -----------

# relevant directories
indir  = joinpath(@__DIR__,"data")
outdir = joinpath(@__DIR__,"results")

# files to process
infiles  = readdir(indir, join=true)
outfiles = joinpath.(outdir, basename.(infiles))
nfiles   = length(infiles)

status = pmap(1:nfiles) do i
  try
    process(infiles[i], outfiles[i])
    true # success
  catch e
    @warn "failed to process $(infiles[i])"
    false # failure
  end
end
