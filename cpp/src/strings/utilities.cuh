/*
 * Copyright (c) 2019, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#pragma once

#include <cuda_runtime.h>
#include <bitmask/legacy/valid_if.cuh>
#include <cudf/strings/string_view.cuh>
#include <cudf/column/column_view.hpp>

#include <cstring>
#include <thrust/scan.h>

namespace cudf
{
namespace strings
{
namespace detail
{

/**
 * @brief This utility will copy the argument string's data into
 * the provided buffer.
 *
 * @param buffer Device buffer to copy to.
 * @param d_string String to copy.
 * @return Points to the end of the buffer after the copy.
 */
__device__ inline char* copy_string( char* buffer, const string_view& d_string )
{
    memcpy( buffer, d_string.data(), d_string.size_bytes() );
    return buffer + d_string.size_bytes();
}

/**
 * @brief Create an offsets column to be a child of a strings column.
 * This will set the offsets values by executing scan on the provided
 * Iterator.
 *
 * @tparam Iterator Used as input to scan to set the offset values.
 * @param begin The beginning of the input sequence
 * @param end The end of the input sequence
 * @param mr Memory resource to use.
 * @param stream Stream to use for any kernel calls.
 * @return offsets child column for strings column
 */
template <typename InputIterator>
std::unique_ptr<column> make_offsets_child_column( InputIterator begin, InputIterator end,
    rmm::mr::device_memory_resource* mr = rmm::mr::get_default_resource(),
    cudaStream_t stream = 0)
{
    CUDF_EXPECTS(begin < end, "Invalid iterator range");
    auto count = thrust::distance(begin, end);
    auto offsets_column = make_numeric_column(
          data_type{INT32}, count + 1, mask_state::UNALLOCATED, stream, mr);
    auto offsets_view = offsets_column->mutable_view();
    auto d_offsets = offsets_view.template data<int32_t>();
    // Using inclusive-scan to compute last entry which is the total size.
    // Exclusive-scan is possible but will not compute that last entry.
    // Rather than manually computing the final offset using values in device memory,
    // we use inclusive-scan on a shifted output (d_offsets+1) and then set the first
    // offset values to zero manually.
    thrust::inclusive_scan(rmm::exec_policy(stream)->on(stream), begin, end,
                           d_offsets+1);
    CUDA_TRY(cudaMemsetAsync(d_offsets, 0, sizeof(int32_t), stream));
    return offsets_column;
}

/**
 * @brief Utility to create a null mask for a strings column using a custom function.
 *
 * @tparam BoolFn Function should return true/false given index for a strings column.
 * @param strings_count Number of strings for the column.
 * @param bfn The custom function used for identifying null string entries.
 * @param mr Memory resource to use.
 * @param stream Stream to use for any kernel calls.
 * @return Pair including null mask and null count
 */
template <typename BoolFn>
std::pair<rmm::device_buffer,cudf::size_type> make_null_mask( cudf::size_type strings_count,
    BoolFn bfn,
    rmm::mr::device_memory_resource* mr = rmm::mr::get_default_resource(),
    cudaStream_t stream = 0)
{
    auto valid_mask = valid_if( static_cast<const bit_mask_t*>(nullptr),
                                bfn, strings_count, stream );
    auto null_count = valid_mask.second;
    rmm::device_buffer null_mask;
    if( null_count > 0 )
        null_mask = rmm::device_buffer(valid_mask.first,
                                       gdf_valid_allocation_size(strings_count),
                                       stream,mr); // does deep copy
    RMM_TRY( RMM_FREE(valid_mask.first,stream) ); // TODO valid_if to return device_buffer in future
    return std::make_pair(null_mask,null_count);
}

} // namespace detail
} // namespace strings
} // namespace cudf
