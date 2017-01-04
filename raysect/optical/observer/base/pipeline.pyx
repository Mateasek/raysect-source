# cython: language_level=3

# Copyright (c) 2014-2016, Dr Alex Meakins, Raysect Project
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

cdef class _PipelineBase:
    """
    base class defining internal interfaces to image processing pipeline
    """

    cpdef object _base_initialise(self, tuple pixel_config, int pixel_samples, int spectral_samples, double lower_wavelength, double upper_wavelength, list spectral_slices):
        """
        setup internal buffers (e.g. frames)
        reset internal statistics as appropriate
        etc..

        :return:
        """
        raise NotImplementedError("Virtual method must be implemented by a sub-class.")

    cpdef PixelProcessor _base_pixel_processor(self, tuple pixel_id, int slice_id):
        raise NotImplementedError("Virtual method must be implemented by a sub-class.")

    cpdef object _base_update(self, tuple pixel_id, int slice_id, tuple packed_result):
        raise NotImplementedError("Virtual method must be implemented by a sub-class.")

    cpdef object _base_finalise(self):
        raise NotImplementedError("Virtual method must be implemented by a sub-class.")


cdef class Pipeline2D(_PipelineBase):
    """
    """

    cpdef object initialise(self, tuple pixels, int pixel_samples, int spectral_samples, double lower_wavelength, double upper_wavelength, list spectral_slices):
        raise NotImplementedError("Virtual method must be implemented by a sub-class.")

    cpdef PixelProcessor pixel_processor(self, int x, int y, int slice_id):
        raise NotImplementedError("Virtual method must be implemented by a sub-class.")

    cpdef object update(self, int x, int y, int slice_id, tuple packed_result):
        raise NotImplementedError("Virtual method must be implemented by a sub-class.")

    cpdef object finalise(self):
        raise NotImplementedError("Virtual method must be implemented by a sub-class.")

    cpdef object _base_initialise(self, tuple pixel_config, int pixel_samples, int spectral_samples, double lower_wavelength, double upper_wavelength, list spectral_slices):
        self.initialise(pixel_config, pixel_samples, spectral_samples, lower_wavelength, upper_wavelength, spectral_slices)

    cpdef object _base_update(self, tuple pixel_id, int slice_id, tuple packed_result):
        cdef int x, y
        x, y = pixel_id
        self.update(x, y, slice_id, packed_result)

    cpdef object _base_finalise(self):
        self.finalise()

    cpdef PixelProcessor _base_pixel_processor(self, tuple pixel_id, int slice_id):
        cdef int x, y
        x, y = pixel_id
        return self.pixel_processor(x, y, slice_id)

