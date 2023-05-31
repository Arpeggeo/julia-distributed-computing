using Distributed

# instantiate and precompile environment
@everywhere begin
  using Pkg; Pkg.activate(@__DIR__)
  Pkg.instantiate(); Pkg.precompile()
end

# load dependencies and helper functions
@everywhere begin
  using ProgressMeter
  using CSV

  function process(infile, outfile)
    # read file from disk
    csv = CSV.File(infile)

    # perform calculations
    sleep(60)

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

# process files in parallel
status = @showprogress pmap(1:nfiles) do i
  try
    process(infiles[i], outfiles[i])
    true # success
  catch e
    false # failure
  end
end

# report files that failed
failed = infiles[.!status]
if !isempty(failed)
  println("List of files that failed:")
  foreach(println, failed)
end
