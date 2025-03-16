using DataFrames, CSV
using WGLMakie, GeoJSON, GeoMakie
using GeometryBasics
using ColorSchemes
using Bonito
function get_data_for_year(year::Int, df, country_name)
    idx = findfirst(==(year), df.Year)
    return isnothing(idx) ? nothing : df[idx, country_name]
end

function load_dataset(filename)
    df = DataFrame(CSV.File(filename, normalizenames=true))  
    dropmissing!(df, :Year)

    valid_countries = [(col, country_map[col]...) for col in names(df)[2:end] if haskey(country_map, col)]
    valid_columns = vcat("Year", [c[1] for c in valid_countries])

    select!(df, valid_columns)
    return df, Dict(col => (lat, lon) for (col, lat, lon) in valid_countries)
end

country_coords = DataFrame(CSV.File("data/country-coord.csv", normalizenames=true))
country_map = Dict(row.Country => (row.Latitude, row.Longitude) for row in eachrow(country_coords))

df_emission, valid_countries_emission = load_dataset("data/export_emissions2.csv")
df_forest, valid_countries_forest = load_dataset("data/deforest.csv")

datasets = Dict(
    "Emissions" => (df_emission, valid_countries_emission),
    "Deforestation" => (df_forest, valid_countries_forest)
)
datasets_hi_lo = Dict(
    "Emissions" => (800, 0.0),
    "Deforestation" => (50, -0.00792)
)
App() do session  
    year = Observable(2000)
    selected_dataset = Observable("Emissions")
    fig = Figure(backgroundcolor = RGBf(0.98, 0.98, 0.98))
    colsize!(fig.layout, 1, Relative(0.7))  
    rowsize!(fig.layout, 1, Relative(0.6))  
    ga = GeoAxis(fig[1, 1], dest="+proj=wintri", aspect=1.5)
    lines!(ga, GeoMakie.coastlines())
    cmap = cgrad([:blue, :red], rev=false)
    cb = Colorbar(fig[1, 2], colormap=cmap, width=10, ticksvisible = false,ticklabelsvisible=false)
    year_text = Observable("Year: $(year[])")
    year_label = Label(fig[1, 3], year_text, fontsize=20, tellwidth=false)
    scatter_plot = Observable(Point2f[])
    scatter_colors = Observable(RGB{Float64}[])
    scatter_sizes = Observable(Float64[])
    function update_plot()
        df, valid_countries = datasets[selected_dataset[]]
        highest_emission, lowest_emission = datasets_hi_lo[selected_dataset[]]
        emissions = [get_data_for_year(year[], df, country_name) for country_name in keys(valid_countries)]
        mask = .!(ismissing.(emissions))
        emissions = emissions[mask]
        coords = [valid_countries[c] for (c, keep) in zip(keys(valid_countries), mask) if keep]
        norm_emissions = [(e - lowest_emission) / (highest_emission - lowest_emission + 1e-9) for e in emissions]
        sizes = [3 + n * (6 - 3) for n in norm_emissions]
        colors = [RGB(n, 0, 1 - n) for n in norm_emissions]
        empty!(scatter_plot[])
        empty!(scatter_colors[])
        empty!(scatter_sizes[])
        append!(scatter_plot[], [Point2f(lon, lat) for (lat, lon) in coords])
        append!(scatter_colors[], colors)
        append!(scatter_sizes[], sizes)
        notify(scatter_plot)
        notify(scatter_colors)
        notify(scatter_sizes)
        year_text[] = "Year: $(year[])"
    end
    scatter!(ga, scatter_plot; color=scatter_colors, markersize=scatter_sizes)
    year_slider = D.Slider("Year", 1989:2023, value=year[])
    dataset_menu = D.Dropdown("Data: ", ["Emissions", "Deforestation"])
    on(year_slider.value) do v
        year[] = v
        update_plot()
    end
    on(dataset_menu.value) do new_selection
        selected_dataset[] = new_selection  # This updates the dataset dynamically
        update_plot()
    end
    update_plot()
    style = Styles(
        CSS("font-weight" => "500"),
        CSS(":hover", "background-color" => "silver"),
        CSS(":focus", "box-shadow" => "rgba(0, 0, 0, 0.5) 0px 0px 5px"),
    )
    animate_button = D.Button("Animate")
    function animate_years()
        @async begin
            for y in 1989:2023
                year[] = y
                update_plot()
                sleep(0.1)
                yield() 
            end
        end  
    end
    on(animate_button.value) do click::Bool
        @async animate_years()
    end
    return DOM.div(
        D.FlexCol(fig,D.FlexRow(year_slider, dataset_menu,animate_button))
    )
end