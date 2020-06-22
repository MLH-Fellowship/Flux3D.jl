# export TriMesh,
#     load_trimesh,
#     compute_vertex_normals,
#     compute_face_normals,
#     compute_face_normals,
#     compute_face_areas,
#     get_edges,
#     get_laplacian_sparse,
#     get_faces_to_edges,
#     get_edges_to_key

# import GeometryBasics
# import GeometryBasics:
#     Point3f0, GLTriangleFace, NgonFace, convert_simplex, Mesh, meta, triangle_mesh

# TODO: add texture fields
mutable struct BatchedTriMesh{T,R} <: AbstractMesh
    N::Int64
    V::Int64
    F::Int64
    equalised::Bool
    valid::AbstractArray{Bool, 1}
    offset::Int8
    _verts_len::AbstractArray{Int,1}
    _faces_len::AbstractArray{Int,1}

    _verts_packed::Union{Nothing, AbstractArray{T,2}}
    _verts_padded::Union{Nothing, AbstractArray{T,3}}
    _verts_list::Union{Nothing, AbstractArray{<:AbstractArray{T,2},1}}

    _faces_packed::Union{Nothing, AbstractArray{R,2}}
    _faces_padded::Union{Nothing, AbstractArray{R,3}}
    _faces_list::Union{Nothing, AbstractArray{<:AbstractArray{R,2},1}}

    _edges_packed::Union{Nothing, AbstractArray{R,2}}
    _faces_to_edges_packed::Union{Nothing, AbstractArray{R,2}}
    _laplacian_packed::Union{Nothing,AbstractSparseMatrix{T,R}}

    _edges_to_key::Union{Nothing,Dict{Tuple{R,R},R}}
end

# TODO: Add contructor according to batched format
function BatchedTriMesh(
    verts::AbstractArray{<:AbstractArray{T,2},1},
    faces::AbstractArray{<:AbstractArray{R,2},1};
    offset::Number = -1
)   where {T,R}

    length(verts) == length(faces) || error("batch size of verts and faces should match, $(length(verts)) != $(length(faces))")
    _verts_len = size.(verts, 1)
    _faces_len = size.(faces, 1)
    N = length(verts)
    V = maximum(_verts_len)
    F = maximum(_faces_len)
    equalised = all(_verts_len .== V) && all(_faces_len .== F)
    valid = _faces_len .> 0
    offset = Int8(offset)

    _verts_list = verts
    _faces_list = faces

    return BatchedTriMesh(N,V,F,equalised,valid,offset,_verts_len,_faces_len,
                   nothing, nothing,_verts_list, nothing, nothing,_faces_list,
                   nothing, nothing, nothing, nothing)
end

function BatchedTriMesh(m::GeometryBasics.Mesh)
    (verts, faces) = _load_meta(m)
    TriMesh([verts], [faces])
end

# covert (verts, faces) to GeometryBasics Mesh
function GBMesh(verts::AbstractArray{T,2}, faces::AbstractArray{R,2}) where {T,R}
    points = Point3f0[
        GeometryBasics.Point{3,Float32}(verts[i, :]) for i = 1:size(verts, 1)
    ]
    vert_len = size(m.faces, 2)
    poly_face = NgonFace{vert_len,UInt32}[
        NgonFace{vert_len,UInt32}(faces[i, :]) for i = 1:size(faces, 1)
    ]
    # faces = convert_simplex.(GLTriangleFace, poly_face)
    faces = GLTriangleFace.(poly_face)
    return Mesh(meta(points), faces)
end

# function GBMesh(m::BatchedTriMesh)
#     verts_list = get_verts_list(m)
#     faces_list = get_faces_list(m)
#     gbmeshes = [GBMesh(verts[i], faces[i]) for i = 1:m.N]
#     return gbmeshes
# end

GBMesh(m::TriMesh) = GBMesh(m.vertices, m.faces)
# GBMesh(m::BatchedTriMesh) = GBMesh(m.vertices, m.faces)

function _load_meta(m::GeometryBasics.Mesh)
    if !(m isa GeometryBasics.Mesh{3,Float32,<:GeometryBasics.Triangle})
        m = triangle_mesh(m)
    end
    vs = m.position
    vertices = [reshape(Array(v), 1, :) for v in vs]
    vertices = reduce(vcat, vertices)
    fs = getfield(getfield(m, :simplices), :faces)
    faces = [reshape(Array(UInt32.(f)), 1, :) for f in fs]
    faces = reduce(vcat, faces)
    return (vertices, faces)
end

_get_offset(x::GeometryBasics.OffsetInteger{o,T}) where {o,T} = o

function load_trimesh(fn; elements_types...)
    mesh = load(fn; elements_types...)
    verts, faces = _load_meta(mesh)
    # # offset = _get_offset(x)   #offset is always -1 when loaded from MeshIO
    return BatchedTriMesh([verts], [faces])
end

# # TODO: extend save function for obj file (as it is not implemented yet) and use that function here
# function save_trimesh(file_name, mesh::TriMesh)
#     error("Not implemented")
# end

function Base.setproperty!(m::BatchedTriMesh, f::Symbol, v)
    if (f==:_verts_packed) || (f==:_verts_padded) || (f==:_verts_list)
        if (f == :_verts_packed) && (getproperty(m,f) !== v)
            setfield!(m, f, convert(fieldtype(typeof(m), f), v))
            setfield!(m, :verts_padded, nothing)
            _compute_verts_list(m, true)
        elseif (f == :_verts_padded) && (getproperty(m,f) !== v)
            setfield!(m, f, convert(fieldtype(typeof(m), f), v))
            setfield!(m, :verts_packed, nothing)
            _compute_verts_list(m, true)
        elseif (f == :_verts_list) && (getproperty(m,f) !== v)
            setfield!(m, f, convert(fieldtype(typeof(m), f), v))
            setfield!(m, :verts_packed, nothing)
            setfield!(m, :verts_padded, nothing)
    else
        setfield!(m, f, convert(fieldtype(typeof(m), f), v))
    end
end

function get_verts_packed(m::BatchedTriMesh; refresh::Bool = false)
    _compute_verts_packed(m, refresh)
    return m._verts_packed
end

function get_verts_padded(m::BatchedTriMesh; refresh::Bool = false)
    _compute_verts_padded(m, refresh)
    return m._verts_padded
end

function get_verts_list(m::BatchedTriMesh; refresh::Bool = false)
    return m._verts_list
end

function _compute_verts_packed(m::BatchedTriMesh, refresh::Bool = false)
    if refresh || (m._verts_packed isa Nothing)
        verts_packed = _list_to_packed(m._verts_list)
        setfield!(m, :_verts_packed, verts_packed)
    end
end

function _compute_verts_padded(m::BatchedTriMesh, refresh::Bool = false)
    if refresh || (m._verts_padded isa Nothing)
        verts_padded = _list_to_padded(m._verts_list, 0, (m.V, 3))
        setfield!(m, :_verts_padded, verts_padded)
    end
end

function _compute_verts_list(m::BatchedTriMesh, refresh::Bool = false)
    if refresh || (m._verts_list isa Nothing)
        if m._verts_packed !== nothing
            verts_list = _packed_to_list(m._verts_packed, m._verts_len)
        elseif m._verts_padded !== nothing
            verts_list = _padded_to_list(m._verts_padded, m._verts_len)        
        else
            error("not possible to contruct list without padded and packed")
        end
        setfield!(m, :_verts_list, verts_list)
    end
end

function get_faces_packed(m::BatchedTriMesh, refresh::Bool = false)
    _compute_faces_packed(m, refresh)
    return m._faces_packed
end

function get_faces_padded(m::BatchedTriMesh, refresh::Bool = false)
    _compute_faces_padded(m, refresh)
    return m._faces_padded
end

function get_faces_list(m::BatchedTriMesh, refresh::Bool = false)
    return m._faces_list
end

function _compute_faces_packed(m::BatchedTriMesh, refresh::Bool = false)
    if refresh || (m._faces_packed isa Nothing)
        faces_packed = _list_to_packed(m._faces_list)
        _,verts_packed_first_idx,_ = _auxiliary_mesh(m._verts_list)
        _,_,faces_packed_list_idx = _auxiliary_mesh(m._faces_list)
        faces_packed_offset = verts_packed_first_idx[faces_packed_list_idx] .- -1
        faces_packed = faces_packed .+ faces_packed_offset
        setfield!(m, :_faces_packed, faces_packed)
    end
end

function _compute_faces_padded(m::BatchedTriMesh, refresh::Bool = false)
    if refresh || (m._faces_padded isa Nothing)
        faces_padded = _list_to_padded(m._faces_list, 0, (m.F, 3))
        setfield!(m, :_faces_padded, faces_padded)
    end
end

function get_edges_packed(m::BatchedTriMesh, refresh::Bool = false)
    _compute_edges_packed(m, refresh)
    return m._edges_packed
end

function get_edges_to_key(m::BatchedTriMesh, refresh::Bool = false)
    _compute_edges_packed(m, refresh)
    return m._edges_to_key
end

function get_faces_to_edges_packed(m::BatchedTriMesh, refresh::Bool = false)
    _compute_edges_packed(m, refresh)
    return m._faces_to_edges_packed
end

function _compute_edges_packed(m::BatchedTriMesh, refresh::Bool = false)
    if refresh || (any([m._edges_packed, m._edges_to_key, m._faces_to_edges_packed] .=== nothing))

        faces = get_faces_packed(m)
        verts = get_verts_packed(m)

        e12 = cat(faces[:, 1], faces[:, 2], dims = 2)
        e23 = cat(faces[:, 2], faces[:, 3], dims = 2)
        e31 = cat(faces[:, 3], faces[:, 1], dims = 2)

        # Sort edges (v0, v1) such that v0 <= v1
        e12 = sort(e12; dims = 2)
        e23 = sort(e23; dims = 2)
        e31 = sort(e31; dims = 2)

        # Edges including duplicates
        edges = cat(e12, e23, e31, dims = 1)

        # Converting edge (v0, v1) into integer hash, ie. (V+1)*v0 + v1.
        # There will be no collision, which is asserted by (V+1), as 1<=v0<=V.
        V_hash = size(verts, 1) + 1
        edges_hash = (V_hash .* edges[:, 1]) .+ edges[:, 2]

        # Sort and remove duplicate edges_hash
        sort!(edges_hash)
        unique!(edges_hash)

        # Convert edges_hash to edges
        edges = cat((edges_hash .÷ V_hash), (edges_hash .% V_hash); dims = 2)

        # Edges to key
        edges_to_key = Dict{Tuple{UInt32,UInt32},UInt32}([
            (Tuple(edges[i, :]), i) for i = 1:size(edges, 1)
        ])

        # e12 -> tuple -> get
        e12_tup = [Tuple(e12[i, :]) for i = 1:size(e12, 1)]
        e23_tup = [Tuple(e23[i, :]) for i = 1:size(e23, 1)]
        e31_tup = [Tuple(e31[i, :]) for i = 1:size(e31, 1)]
        faces_to_edges_tuple = cat(e23_tup, e31_tup, e12_tup; dims = 2)

        faces_to_edges = map(x -> get(edges_to_key, x, -1), faces_to_edges_tuple)

        m._edges_packed = edges
        m._edges_to_key = edges_to_key
        m._faces_to_edges_packed = faces_to_edges
    end
end


function get_laplacian_packed(m::BatchedTriMesh, refresh::Bool = false)
    _compute_laplacian_packed(m, refresh)
    return m._laplacian_packed
end

get_laplacian_sparse(m::BatchedTriMesh, refresh::Bool = false) = get_laplacian_packed(m, refresh)

function _compute_laplacian_packed(m::BatchedTriMesh, refresh::Bool = false)
    if refresh || (m._laplacian_packed isa Nothing)
        verts = get_verts_packed(m)
        edges = get_edges_packed(m)

        e1 = edges[:, 1]
        e2 = edges[:, 2]

        idx12 = cat(e1, e2, dims = 2)
        idx21 = cat(e2, e1, dims = 2)
        idx = cat(idx12, idx21, dims = 1)

        A = sparse(
            idx[:, 1],
            idx[:, 2],
            ones(Float32, size(idx, 1)),
            size(verts, 1),
            size(verts, 1),
        )

        deg = Array{Float32}(sum(A, dims = 2))  # TODO: will be problematic for GPU

        deg1 = map(x -> (x > 0 ? 1 / x : x), deg[e1])
        deg2 = map(x -> (x > 0 ? 1 / x : x), deg[e2])
        diag = fill(-1.0f0, size(verts, 1))

        Is = cat(e1, e2, UInt32.(1:size(verts, 1)); dims = 1)
        Js = cat(e2, e1, UInt32.(1:size(verts, 1)); dims = 1)
        Vs = cat(deg1, deg2, diag; dims = 1)
        m._laplacian_packed = sparse(Is, Js, Vs, size(verts, 1), size(verts, 1))
    end
end

function compute_verts_normals_packed(m::BatchedTriMesh)
    
    verts = get_verts_packed(m)
    faces = get_faces_packed(m)
    
    vert_faces = verts[faces, :]
    vertex_normals = Zygote.bufferfrom(zeros(Float32, size(verts)...))

    vertex_normals[faces[:, 1], :] += _lg_cross(
        vert_faces[:, 2, :] - vert_faces[:, 1, :],
        vert_faces[:, 3, :] - vert_faces[:, 1, :],
    )
    vertex_normals[faces[:, 2], :] += _lg_cross(
        vert_faces[:, 3, :] - vert_faces[:, 2, :],
        vert_faces[:, 1, :] - vert_faces[:, 2, :],
    )
    vertex_normals[faces[:, 3], :] += _lg_cross(
        vert_faces[:, 1, :] - vert_faces[:, 3, :],
        vert_faces[:, 2, :] - vert_faces[:, 3, :],
    )

    return _normalize(copy(vertex_normals), dims = 2)
end

function compute_verts_normals_padded(m::BatchedTriMesh)
    normals_packed = compute_verts_normals_packed(m)
    normals_padded = _packed_to_padded(normals_packed, m._verts_len, 0.0)
    return normals_padded
end

function compute_verts_normals_list(m::BatchedTriMesh)
    normals_packed = compute_verts_normals_packed(m)
    normals_list = _packed_to_list(normals_packed, m._verts_len)
    return normals_list
end

function compute_faces_normals_packed(m::BatchedTriMesh)
    verts = get_verts_packed(m)
    faces = get_faces_packed(m)

    vert_faces = verts[faces, :]
    face_normals = _lg_cross(
        vert_faces[:, 2, :] - vert_faces[:, 1, :],
        vert_faces[:, 3, :] - vert_faces[:, 1, :],
    )
    return _normalize(face_normals, dims = 2)
end

function compute_faces_normals_padded(m::BatchedTriMesh)
    normals_packed = compute_faces_normals_packed(m)
    normals_padded = _packed_to_padded(normals_packed, m._faces_len, 0.0)
    return normals_padded
end

function compute_faces_normals_list(m::BatchedTriMesh)
    normals_packed = compute_faces_normals_packed(m)
    normals_list = _packed_to_list(normals_packed, m._faces_len)
    return normals_list
end

function compute_faces_areas_packed(m::BatchedTriMesh; compute_normals::Bool = true, eps::Number = 1e-6)
    verts = get_verts_packed(m)
    faces = get_faces_packed(m)
    
    vert_faces = verts[faces, :]
    face_normals_vec = _lg_cross(
        vert_faces[:, 2, :] - vert_faces[:, 1, :],
        vert_faces[:, 3, :] - vert_faces[:, 1, :],
    )
    face_norm = sqrt.(sum(face_normals_vec .^ 2, dims = 2))
    face_areas = dropdims(face_norm ./ 2; dims = 2)
    if compute_normals
        face_normals = face_normals_vec ./ max.(face_norm, eps)
    else
        face_normals = nothing
    end
    return (face_areas, face_normals)
end

function compute_faces_areas_padded(m::BatchedTriMesh; compute_normals::Bool = true, eps::Number = 1e-6)
    if compute_normals
        areas_packed, normals_packed = compute_faces_areas_packed(m; compute_normals=compute_normals, eps=eps)
        areas_padded = _packed_to_padded(areas_packed, m._faces_len, 0.0)
        normals_padded = _packed_to_padded(normals_packed, m._faces_len, 0.0)
        return (areas_padded, normals_padded)
    else
        areas_packed = compute_faces_areas_packed(m; compute_normals=compute_normals, eps=eps)
        areas_padded = _packed_to_padded(areas_packed, m._faces_len, 0.0)
        return areas_padded
    end
end

function compute_faces_areas_list(m::BatchedTriMesh; compute_normals::Bool = true, eps::Number = 1e-6)
    if compute_normals
        areas_packed, normals_packed = compute_faces_areas_packed(m; compute_normals=compute_normals, eps=eps)
        areas_list = _packed_to_list(areas_packed, m._faces_len)
        normals_list = _packed_to_list(normals_packed, m._faces_len)
        return (areas_list, normals_list)
    else
        areas_packed = compute_faces_areas_packed(m; compute_normals=compute_normals, eps=eps)
        areas_list = _packed_to_list(areas_packed, m._faces_len)
        return areas_list
    end
end
