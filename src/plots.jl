module plots

import ..data_objects: DataSet, DataContainer
import ..utils: Axis, StringOrArray
using PyCall
@pyimport yt.visualization.plot_window as pw
@pyimport yt.visualization.profile_plotter as pp

abstract YTPlot

type SlicePlot <: YTPlot
    plot::PyObject
    function SlicePlot(ds::DataSet, axis::Axis, fields::StringOrArray;
                       args...)
        new(pw.SlicePlot(ds.ds, axis, fields; args...))
    end
end

type ProjectionPlot <: YTPlot
    plot::PyObject
    function ProjectionPlot(ds::DataSet, axis::Axis, fields::StringOrArray;
                            data_source=nothing, args...)
        if data_source != nothing
            source = data_source.cont
        else
            source = pybuiltin("None")
        end
        new(pw.ProjectionPlot(ds.ds, axis, fields, data_source=source; args...))
    end
end

type PhasePlot <: YTPlot
    plot::PyObject
    function PhasePlot(dc::DataContainer, x_field::String, y_field::String,
                       z_fields::StringOrArray; args...)
        new(pp.PhasePlot(dc.cont, x_field, y_field, z_fields; args...))
    end
end

type ProfilePlot <: YTPlot
    plot::PyObject
    function ProfilePlot(dc::DataContainer, x_field::String,
                         y_fields::StringOrArray; args...)
        new(pp.ProfilePlot(dc.cont, x_field, y_fields; args...))
    end
end

# Plot methods

function show_plot(plot::YTPlot)
    plot.plot
end

function call(plot::YTPlot)
    pywrap(plot.plot)
end

function save_plot(plot::YTPlot; args...)
    pywrap(plot.plot).save(args...)
end

end
