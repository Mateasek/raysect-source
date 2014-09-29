# cython: language_level=3

# Copyright (c) 2014, Dr Alex Meakins, Raysect Project
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     1. Redistributions of source code must retain the above copyright notice,
#        this list of conditions and the following disclaimer.
#
#     2. Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#
#     3. Neither the name of the Raysect Project nor the names of its
#        contributors may be used to endorse or promote products derived from
#        this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

cimport cython
from libc.math cimport sqrt
from raysect.core.math.affinematrix cimport AffineMatrix
from raysect.core.math.point cimport Point
from raysect.core.math.vector cimport Vector, new_vector
from raysect.core.math.normal cimport Normal
from raysect.core.scenegraph.primitive cimport Primitive
from raysect.core.scenegraph.world cimport World
from raysect.optical.spectrum cimport Spectrum
from raysect.optical.ray cimport Ray
from raysect.core.math.function cimport autowrap_function1d, autowrap_function2d

cdef class Sellmeier(Function1D):

    def __init__(self, double b1, double b2, double b3, double c1, double c2, double c3):

        self.b1 = b1
        self.b2 = b2
        self.b3 = b3

        self.c1 = c1
        self.c2 = c2
        self.c3 = c3

    @cython.cdivision(True)
    cdef double evaluate(self, double wavelength) except *:

        cdef double w2 = wavelength * wavelength * 1e-6

        # TODO: prevent div by zero

        return sqrt(1 + (self.b1 * w2) / (w2 - self.c1)
                      + (self.b2 * w2) / (w2 - self.c2)
                      + (self.b3 * w2) / (w2 - self.c3))


# note transmission defined as attenuation per meter

cdef class Glass(Material):

    def __init__(self, object index, object transmission, cutoff = 1e-6):

        self.index = autowrap_function1d(index)
        self.transmission = autowrap_function2d(transmission)
        self.cutoff = cutoff

    cpdef Spectrum evaluate_surface(self, World world, Ray ray, Primitive primitive, Point hit_point,
                                    bint exiting, Point inside_point, Point outside_point,
                                    Normal normal, AffineMatrix to_local, AffineMatrix to_world):

        cdef:
            Vector incident, reflected, transmitted
            double c1, c2s, n1, n2, gamma, reflectivity, transmission, temp
            Spectrum spectrum, ray_sample

        # convert ray direction normal to local coordinates
        incident = ray.direction.transform(to_local)

        # ensure vectors are normalised for reflection calculation
        incident = incident.normalise()
        normal = normal.normalise()

        # calculate cosine of angle between incident and normal
        c1 = -normal.dot(incident)

        # are we entering or leaving material - calculate refractive change
        if exiting:

            # leaving material
            n1 = self.index.evaluate(ray.refraction_wavelength)
            n2 = 1.0

        else:

            # entering material
            n1 = 1.0
            n2 = self.index.evaluate(ray.refraction_wavelength)

        with cython.cdivision:

            gamma = n1 / n2

        # calculate square of cosine of angle between transmitted ray and normal
        c2s = 1 - (gamma * gamma) * (1 - c1 * c1)

        # check for total internal reflection
        if c2s <= 0:

            # total internal reflection
            temp = 2 * c1
            reflected = new_vector(incident.x + temp * normal.x,
                                   incident.y + temp * normal.y,
                                   incident.z + temp * normal.z)

            # convert reflected ray direction to world space
            reflected = reflected.transform(to_world)

            # spawn reflected ray and trace
            if exiting:

                # incident ray is pointing out of surface, reflection is therefore inside
                reflected_ray = ray.spawn_daughter(inside_point.transform(to_world), reflected)

            else:

                # incident ray is pointing in to surface, reflection is therefore outside
                reflected_ray = ray.spawn_daughter(outside_point.transform(to_world), reflected)

            return reflected_ray.trace(world)

        else:

            # calculate reflected and transmitted ray normals
            temp = 2 * c1
            reflected = new_vector(incident.x + temp * normal.x,
                                   incident.y + temp * normal.y,
                                   incident.z + temp * normal.z)

            if exiting:

                temp = gamma * c1 + sqrt(c2s)
                transmitted = new_vector(gamma * incident.x + temp * normal.x,
                                         gamma * incident.y + temp * normal.y,
                                         gamma * incident.z + temp * normal.z)

            else:

                temp = gamma * c1 - sqrt(c2s)
                transmitted = new_vector(gamma * incident.x + temp * normal.x,
                                         gamma * incident.y + temp * normal.y,
                                         gamma * incident.z + temp * normal.z)

            # calculate fresnel reflection and transmission coefficients
            self._fresnel(c1, -normal.dot(transmitted), n1, n2, &reflectivity, &transmission)

            # convert reflected and transmitted rays to world space
            reflected = reflected.transform(to_world)
            transmitted = transmitted.transform(to_world)

            # convert origin points to world space
            inside_point = inside_point.transform(to_world)
            outside_point = outside_point.transform(to_world)

            # spawn reflected and transmitted rays
            if exiting:

                # incident ray is pointing out of surface
                reflected_ray = ray.spawn_daughter(inside_point, reflected)
                transmitted_ray = ray.spawn_daughter(outside_point, transmitted)

            else:

                # incident ray is pointing in to surface
                reflected_ray = ray.spawn_daughter(outside_point, reflected)
                transmitted_ray = ray.spawn_daughter(inside_point, transmitted)

            # trace rays and return results
            if reflectivity > self.cutoff:

                spectrum = reflected_ray.trace(world)
                spectrum.mul_scalar(reflectivity)

            else:

                spectrum = ray.new_spectrum()

            if transmission > self.cutoff:

                ray_sample = transmitted_ray.trace(world)
                ray_sample.mul_scalar(transmission)
                spectrum.add_array(ray_sample.bins)

            return spectrum

    cdef inline void _fresnel(self, double ci, double ct, double n1, double n2, double *reflectivity, double *transmission):

        with cython.cdivision:

            reflectivity[0] = 0.5 * (((n1*ci - n2*ct) / (n1*ci + n2*ct))**2 + ((n1*ct - n2*ci) / (n1*ct + n2*ci))**2)
            transmission[0] = 1 - reflectivity[0]

    cpdef Spectrum evaluate_volume(self, Spectrum spectrum, World world,
                                   Ray ray, Primitive primitive,
                                   Point start_point, Point end_point,
                                   AffineMatrix to_local, AffineMatrix to_world):

        # TODO: write me!

        #length = start_point.vector_to(end_point).length

        # with cython.cdivision:
        #
        #     power = length / self.transmission_depth
        #
        # attenuation = new_rgb(1 - cpow(self.transmission.r, power),
        #                       1 - cpow(self.transmission.g, power),
        #                       1 - cpow(self.transmission.b, power))

        # return VolumeRGB(new_rgb(0, 0, 0), attenuation)

        return spectrum


def BK7():

    return Glass(index=Sellmeier(1.03961212, 0.231792344, 1.01046945, 6.00069867e-3, 2.00179144e-2, 1.03560653e2),
                 transmission=lambda: 1.0)