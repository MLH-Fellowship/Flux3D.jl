using Gadfly, DataFrames, Cairo

function read_benchmarks(fname, framework)
    isfile(fname) || error("given file location $(fname) is invalid")
    data = DataFrame(
        category = String[],
        device = String[],
        transforms = String[],
        npoints = Int[],
        time_ms = Float64[],
    )
    for line in eachline(fname)
        raw = split(line)
        push!(data,(raw[1], raw[2], raw[3], parse(Int, raw[4]), parse(Float64, raw[5])))
    end
    data[!, :framework] .= framework
    return data
end

function save_benchmarks(fname, bm, category, xlabel)
    # using Theme(background_color = colorant"white")
    # as arg in plot to force white background
    p = plot(
        bm[bm[!,:category] .== category, :],
        xgroup = "transforms",
        ygroup = "device",
        color = "framework",
        x = "npoints",
        y = "time_ms",
        Guide.ylabel("Time (milliseconds)"),
        Guide.xlabel(xlabel),
        Theme(background_color = colorant"white"),
        Geom.subplot_grid(Geom.point, Geom.line, Scale.x_log2, Scale.y_log10),
    )
    draw(PNG(fname, 40cm, 20cm), p)
end

bm_flux3d = read_benchmarks(joinpath(@__DIR__, "bm_flux3d.txt"), "Flux3D.jl")
bm_kaolin = read_benchmarks(joinpath(@__DIR__, "bm_kaolin.txt"), "Kaolin")
bm = vcat(bm_flux3d, bm_kaolin)

save_benchmarks(joinpath(@__DIR__,"pics/bm_pcloud.png"), bm, "PointCloud", "No. of points in PointCloud")
save_benchmarks(joinpath(@__DIR__,"pics/bm_trimesh.png"), bm, "TriMesh", "No. of verts in TriMesh")
save_benchmarks(joinpath(@__DIR__,"pics/bm_metrics.png"), bm, "Metrics", "No. of verts in TriMesh")
