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
from raysect.core.math.utility cimport interpolate,  integrate, find_index, lerp
from numpy cimport PyArray_SimpleNew, PyArray_FILLWBYTE, NPY_FLOAT64, npy_intp, import_array
from numpy import array

# required by numpy c-api
import_array()

cdef class SpectralFunction:
    """
    Spectral function base class.
    """

    cpdef double sample_single(self, double min_wavelength, double max_wavelength):

        return NotImplemented


    cpdef SampledSF sample_multiple(self, double min_wavelength, double max_wavelength, int num_samples):

        return NotImplemented


cdef class SampledSF(SpectralFunction):
    """
    Regularly spaced samples of a spectral function.

    Generated by sampling a spectral function. Used internally by the raytracer.

    samples lie in centre of wavelength bins.
    """

    def __init__(self, double min_wavelength, double max_wavelength, int num_samples, bint fast_sample=False):

        if num_samples < 1:

            raise("Number of samples cannot be less than 1.")

        if min_wavelength <= 0.0 or max_wavelength <= 0.0:

            raise ValueError("Wavelength cannot be less than or equal to zero.")

        if min_wavelength >= max_wavelength:

            raise ValueError("Minimum wavelength cannot be greater or equal to the maximum wavelength.")

        self._construct(min_wavelength, max_wavelength, num_samples, fast_sample)

    property wavelengths:

        def __get__(self):

            self._populate_wavelengths()
            return self._wavelengths

    def __len__(self):

        return self.num_samples

    cpdef bint is_shaped(self, double min_wavelength, double max_wavelength, int num_samples):
        """
        Returns True if the stored samples are consistent with the specified
        wavelength range and sample size.

        :param min_wavelength: The minimum wavelength in nanometers.
        :param max_wavelength: The maximum wavelength in nanometers
        :param num_samples: The number of samples.
        :return: True if the samples are compatible with the range/samples, False otherwise.
        :rtype: boolean
        """

        return self.min_wavelength == min_wavelength and \
               self.max_wavelength == max_wavelength and \
               self.num_samples == num_samples

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.cdivision(True)
    cpdef double sample_single(self, double min_wavelength, double max_wavelength):

        # sanity check
        if self.samples is None:

            raise ValueError("Cannot generate sample as the sample array is None.")

        if self.samples.shape[0] != self.num_samples:

            raise ValueError("Sample array length is inconsistent with num_samples.")

        # require wavelength information for this calculation
        self._populate_wavelengths()

        if self.fast_sample:

            # sample data at bin centre by linearly interpolating
            return interpolate(self._wavelengths, self.samples, 0.5 * (min_wavelength + max_wavelength))

        else:

            # average value obtained by integrating linearly interpolated data and normalising
            return integrate(self._wavelengths, self.samples, min_wavelength, max_wavelength) / (max_wavelength - min_wavelength)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.cdivision(True)
    cpdef SampledSF sample_multiple(self, double min_wavelength, double max_wavelength, int num_samples):

        cdef:
            SampledSF s
            double[::1] s_view
            int index
            double lower_wavelength, upper_wavelength, centre_wavelength, reciprocal

        # sanity check
        if self.samples is None:

            raise ValueError("Cannot generate samples as the sample array is None.")

        if self.samples.shape[0] != self.num_samples:

            raise ValueError("Sample array length is inconsistent with num_samples.")

        # no need to re-sample if data is already the correct shape
        if self.is_shaped(min_wavelength, max_wavelength, num_samples):

            return self

        # create new sample object and obtain a memoryview for fast access
        s = new_sampledsf(min_wavelength, max_wavelength, num_samples)
        s_view = s.samples

        # require wavelength information for this calculation
        self._populate_wavelengths()

        if self.fast_sample:

            # sample data at bin centre by linearly interpolating
            for index in range(num_samples):

                centre_wavelength = min_wavelength + (0.5 + index) * s.delta_wavelength
                s_view[index] = interpolate(self._wavelengths, self.samples, centre_wavelength)

        else:

            # re-sample by averaging data across each bin
            lower_wavelength = min_wavelength
            reciprocal = 1.0 / s.delta_wavelength
            for index in range(num_samples):

                upper_wavelength = min_wavelength + (index + 1) * s.delta_wavelength

                # average value obtained by integrating linearly interpolated data and normalising
                s_view[index] = reciprocal * integrate(self._wavelengths, self.samples, lower_wavelength, upper_wavelength)

                lower_wavelength = upper_wavelength

        return s

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.cdivision(True)
    cdef inline void _construct(self, double min_wavelength, double max_wavelength, int num_samples, bint fast_sample):

        cdef:
            npy_intp size, index
            double[::1] wavelengths_view

        self.min_wavelength = min_wavelength
        self.max_wavelength = max_wavelength
        self.num_samples = num_samples
        self.delta_wavelength = (max_wavelength - min_wavelength) / num_samples
        self.fast_sample = fast_sample

        # create spectral sample bins, initialise with zero
        size = num_samples
        self.samples = PyArray_SimpleNew(1, &size, NPY_FLOAT64)
        PyArray_FILLWBYTE(self.samples, 0)

        # wavelengths is populated on demand
        self._wavelengths = None

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef inline void _populate_wavelengths(self):

        cdef:
            npy_intp size
            int index
            double[::1] w_view

        if self._wavelengths is None:

            # create and populate central wavelength array
            size = self.num_samples
            self._wavelengths = PyArray_SimpleNew(1, &size, NPY_FLOAT64)
            w_view = self._wavelengths

            for index in range(self.num_samples):

                w_view[index] = self.min_wavelength + (0.5 + index) * self.delta_wavelength

    # low level scalar maths functions
    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef inline void add_scalar(self, double value):

        cdef:
            double[::1] samples_view
            npy_intp index

        samples_view = self.samples
        for index in range(samples_view.shape[0]):

            samples_view[index] += value

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef inline void sub_scalar(self, double value):

        cdef:
            double[::1] samples_view
            npy_intp index

        samples_view = self.samples
        for index in range(samples_view.shape[0]):

            samples_view[index] -= value

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef inline void mul_scalar(self, double value):

        cdef:
            double[::1] samples_view
            npy_intp index

        samples_view = self.samples
        for index in range(samples_view.shape[0]):

            samples_view[index] *= value

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.cdivision(True)
    cdef inline void div_scalar(self, double value):

        cdef:
            double[::1] samples_view
            double reciprocal
            npy_intp index

        samples_view = self.samples
        reciprocal = 1.0 / value
        for index in range(samples_view.shape[0]):

            samples_view[index] *= reciprocal

    # low level array maths functions
    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef inline void add_array(self, double[::1] array):

        cdef:
            double[::1] samples_view
            npy_intp index

        samples_view = self.samples
        for index in range(samples_view.shape[0]):

            samples_view[index] += array[index]

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef inline void sub_array(self, double[::1] array):

        cdef:
            double[::1] samples_view
            npy_intp index

        samples_view = self.samples
        for index in range(samples_view.shape[0]):

            samples_view[index] -= array[index]

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef inline void mul_array(self, double[::1] array):

        cdef:
            double[::1] samples_view
            npy_intp index

        samples_view = self.samples
        for index in range(samples_view.shape[0]):

            samples_view[index] *= array[index]

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.cdivision(True)
    cdef inline void div_array(self, double[::1] array):

        cdef:
            double[::1] samples_view
            npy_intp index

        samples_view = self.samples
        for index in range(samples_view.shape[0]):

            samples_view[index] /= array[index]


cdef SampledSF new_sampledsf(double min_wavelength, double max_wavelength, int num_samples):

    cdef SampledSF v

    v = SampledSF.__new__(SampledSF)
    v._construct(min_wavelength, max_wavelength, num_samples, False)

    return v


cdef class InterpolatedSF(SpectralFunction):
    """
    Linearly interpolated spectral function.

    spectral function defined by samples of regular or irregular spacing

    ends are extrapolated. must set ends to zero if you want function to end!
    """

    def __init__(self, object wavelengths, object samples, fast_sample=False):
        """

        :param wavelengths: 1D array of wavelengths in nanometers.
        :param samples: 1D array of spectral samples.
        """

        self.wavelengths = array(wavelengths)
        self.samples = array(samples)
        self.fast_sample = fast_sample

        if self.wavelengths.ndim != 1:

            raise ValueError("Wavelength array must be 1D.")

        if self.samples.shape[0] != self.wavelengths.shape[0]:

            raise ValueError("Wavelength and sample arrays must be the same length.")

    def __call__(self, double wavelength):

        if self.samples is None:

            raise ValueError("Cannot generate samples as the sample array is None.")

        if self.wavelengths is None:

            raise ValueError("Cannot generate wavelengths as the sample array is None.")

        if self.samples.shape[0] != self.wavelengths.shape[0]:

            raise ValueError("Wavelength and sample arrays must be the same length.")

        return interpolate(self.wavelengths, self.samples, wavelength)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.cdivision(True)
    cpdef double sample_single(self, double min_wavelength, double max_wavelength):

        # sanity checks, as the user can modify the arrays
        if self.samples is None:

            raise ValueError("Cannot generate samples as the sample array is None.")

        if self.wavelengths is None:

            raise ValueError("Cannot generate wavelengths as the sample array is None.")

        if self.samples.shape[0] != self.wavelengths.shape[0]:

            raise ValueError("Wavelength and sample arrays must be the same length.")

        if self.fast_sample:

            # sample data at bin centre by linearly interpolating
            return interpolate(self.wavelengths, self.samples, 0.5 * (min_wavelength + max_wavelength))

        else:

            # average value obtained by integrating linearly interpolated data and normalising
            return integrate(self.wavelengths, self.samples, min_wavelength, max_wavelength) / (max_wavelength - min_wavelength)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.cdivision(True)
    cpdef SampledSF sample_multiple(self, double min_wavelength, double max_wavelength, int num_samples):

        cdef:
            SampledSF s
            double[::1] s_view
            int index
            double lower_wavelength, upper_wavelength, reciprocal

        # sanity checks, as the user can modify the arrays
        if self.samples is None:

            raise ValueError("Cannot generate samples as the sample array is None.")

        if self.wavelengths is None:

            raise ValueError("Cannot generate wavelengths as the sample array is None.")

        if self.samples.shape[0] != self.wavelengths.shape[0]:

            raise ValueError("Wavelength and sample arrays must be the same length.")

        # create new sample object and obtain a memoryview for fast access
        s = new_sampledsf(min_wavelength, max_wavelength, num_samples)
        s_view = s.samples

        if self.fast_sample:

            # sample data at bin centre by linearly interpolating
            for index in range(num_samples):

                centre_wavelength = min_wavelength + (0.5 + index) * s.delta_wavelength
                s_view[index] = interpolate(self.wavelengths, self.samples, centre_wavelength)

        else:

            # re-sample by averaging data across each bin
            lower_wavelength = min_wavelength
            reciprocal = 1.0 / s.delta_wavelength
            for index in range(num_samples):

                upper_wavelength = min_wavelength + (index + 1) * s.delta_wavelength

                # average value obtained by integrating linearly interpolated data and normalising
                s_view[index] = reciprocal * integrate(self.wavelengths, self.samples, lower_wavelength, upper_wavelength)

                lower_wavelength = upper_wavelength

        return s


cdef class ConstantSF(SpectralFunction):
    """
    Constant value spectral function
    """

    def __init__(self, double value):

        self.value = value

        # initialise cache
        self.cached_samples = None

    cpdef double sample_single(self, double min_wavelength, double max_wavelength):

        return self.value

    cpdef SampledSF sample_multiple(self, double min_wavelength, double max_wavelength, int num_samples):

        cdef:
            SampledSF s
            double[::1] s_view
            int index
            double lower_wavelength, upper_wavelength, reciprocal

        if self.cached_samples is not None and \
           self.cached_samples.is_shaped(min_wavelength, max_wavelength, num_samples):

            return self.cached_samples

        # generate samples
        s = new_sampledsf(min_wavelength, max_wavelength, num_samples)
        s_view = s.samples
        s_view[:] = self.value

        # update cache
        self.cached_samples = s

        return s
