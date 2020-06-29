#include <limits>
#include <stdint.h>

#include "data_transfer_utils.cuh"
#include "cub/cub.cuh"
#include "tokenizer_utils.cuh"
#include "hash_utils.cuh"
#include "tokenizers.cuh"

__device__ __forceinline__ void __init_data_and_mark_word_start_and_ends(uint32_t* code_points, uint32_t* start_word_indices, 
                                                                         uint32_t* end_word_indices, size_t num_code_points,
                                                                         uint32_t* token_ids, uint8_t* tokens_per_word,
                                                                         uint32_t char_for_thread) {
  // Deal with the start_word_indices array
  if(char_for_thread < num_code_points) { 
    uint32_t val_to_write = std::numeric_limits<uint32_t>::max();
    if((code_points[char_for_thread] != SPACE_CODE_POINT) && (char_for_thread > 0) && (code_points[char_for_thread - 1] == SPACE_CODE_POINT)) {
      val_to_write = char_for_thread;
    }
    start_word_indices[char_for_thread] = val_to_write;

    // Deal with the end_word_indices_aray
    val_to_write = std::numeric_limits<uint32_t>::max();
    if((code_points[char_for_thread] != SPACE_CODE_POINT) && (char_for_thread + 1 < num_code_points) && 
        (code_points[char_for_thread + 1] == SPACE_CODE_POINT)) {
      val_to_write = char_for_thread + 1;
    }
    end_word_indices[char_for_thread] = val_to_write;

    token_ids[char_for_thread] = std::numeric_limits<uint32_t>::max();
    tokens_per_word[char_for_thread] = 0;
  }
}

__device__ __forceinline__ void __mark_sentence_start_and_ends(uint32_t* code_points, uint32_t* sentence_offsets,
                                                               uint32_t* start_word_indices, uint32_t* end_word_indices,
                                                               uint32_t num_sentences, uint32_t char_for_thread) {

  // Ensure the starting character of each sentence is written to the word start array.
  if(char_for_thread <= num_sentences) {
    const uint32_t offset = sentence_offsets[char_for_thread];

    if((char_for_thread < num_sentences) && (code_points[offset] != SPACE_CODE_POINT)) {
      start_word_indices[offset] = offset;
    }

    if((char_for_thread > 0) && (code_points[offset - 1] != SPACE_CODE_POINT)) {
      end_word_indices[offset - 1] = offset;
    }
  }
}

/*
  Writes the index to each thread which points to the start of a word to idx_for_sen_start.

  Params
  -------
  code_points: A pointer to the code points in the sentence after being run through the basic
               GPU tokenizer.

  start_word_indices: An array which will contain the starting index for each word scattered throughout.
                      If an index does not represent a word start, the max uint32_t value is written 
                      to indicate this. A post processing step is required to select all the relevant 
                      values from this array.
  
  end_word_indices: An array which will contain the one past the end index for each word scattered throughout.
                    If an index does not represent a word end, the max uint32_t value is written 
                    to indicate this. A post processing step is required to select all the relevant 
                    values from this array. 

                    It is guaranteed that the same number of indices will be written to each kernel 
                    and that after the select step, the two arrays will be aligned (ie. 
                    start_word_indices[word] and end_word_indices[word] are the start and
                    end for the same word). This is not true before the cub::deviceselect is done.

  num_code_points: The total number of code_points in the code_points array.

  token_ids: The array which will hold the token ids. This kernel initialized all values in this array to
             the max uint32_t. It is assumed that the length of this array is num_code_points.
  
  tokens_per_word: The array which will hold the number of tokens in each word. This kernel initialized all
                   values in this array to 0. It is assumed that the length of this array is num_code_points.
*/
__global__ void init_data_and_mark_word_start_and_ends(uint32_t* code_points, uint32_t* start_word_indices, 
                                                       uint32_t* end_word_indices, size_t num_code_points,
                                                       uint32_t* token_ids, uint8_t* tokens_per_word) {

  uint32_t char_for_thread = blockDim.x * blockIdx.x + threadIdx.x;

  __init_data_and_mark_word_start_and_ends(code_points, start_word_indices, end_word_indices, num_code_points,
                                            token_ids, tokens_per_word, char_for_thread);
}


/*
  Writes the indicies of the characters that start sentences in the start_word_indices array and index 
  of the character after the last character in the sentence to the end_word_indices array. This kernel
  should be called after mark_word_start_and_ends with at least num_sentences total threads.

  Params
  -------
  code_points: A pointer to the code points in the sentence after being run through the basic
               GPU tokenizer.
  
  sentence_offsets: an array containing the index of the starting character of each sentence with
                    an extra space at the end containing the total number of characters. As a result,
                    this array is of length num_sentences + 1.

  start_word_indices: An array which will contain the starting index for each word scattered throughout.
                      If an index does not represent a word start, the max uint32_t value is written 
                      to indicate this. A post processing step is required to select all the relevant 
                      values from this array.
  
  end_word_indices: An array which will contain the one past the end index for each word scattered throughout.
                    If an index does not represent a word end, the max uint32_t value is written 
                    to indicate this. A post processing step is required to select all the relevant 
                    values from this array. 

                    It is guaranteed that the same number of indices will be written to each kernel 
                    and that after the select step, the two arrays will be aligned (ie. 
                    start_word_indices[word] and end_word_indices[word] are the start and
                    end for the same word). This is not true before the cub::deviceselect is done.

  num_sentences: The total number of sentences to be processed.
*/
__global__ void mark_sentence_start_and_ends(uint32_t* code_points, uint32_t* sentence_offsets,
                                             uint32_t* start_word_indices, uint32_t* end_word_indices,
                                             uint32_t num_sentences) {

  uint32_t char_for_thread = blockDim.x * blockIdx.x + threadIdx.x;
  __mark_sentence_start_and_ends(code_points, sentence_offsets, start_word_indices, end_word_indices,
                                 num_sentences, char_for_thread);
}

/* 
  A helper function for gpuWordPieceTokenizer.
  See the spec of gpuWordPieceTokenizer for parameter details. This function 
  takes token_start and token_end as inputs which is the start and end indices 
  for each token in the code_points array.
*/
__device__ __forceinline__ void __wordPieceTokenize(uint32_t* code_points, uint64_t* hash_table, uint64_t* bin_coefficients, 
                                                    uint16_t* bin_offsets, uint32_t* token_ids, const uint32_t token_start, 
                                                    const uint32_t token_end, uint8_t* tokens_per_word, uint16_t  unk_token_id, 
                                                    uint16_t max_word_length, uint32_t outer_hash_a_param, uint32_t outer_hash_b_param, 
                                                    uint16_t num_outer_bins) {

  // The sdbm hash of "##"
  constexpr uint32_t hashtag_hash = 2296000;

  uint32_t end = token_end, start = token_start; 
  const uint32_t word_length = token_end - token_start;  
  uint16_t num_values_tokenized = 0;
                                                   
  if(word_length > max_word_length) {
    start = token_end;
    num_values_tokenized = 1;
    token_ids[token_start] = unk_token_id;
    tokens_per_word[token_start] = num_values_tokenized;
  }

  while(start < token_end) {
    end = token_end;
    int token_id = -1;
    const uint32_t length = token_end - start;
    uint64_t substr_hash = sdbm_hash(code_points + start, length, start == token_start? 0: hashtag_hash);

    while(start < end) {
      token_id = retrieve(substr_hash, outer_hash_a_param, outer_hash_b_param, num_outer_bins, hash_table, bin_coefficients, bin_offsets);
      if(token_id != -1) {
        break;
      }
      --end;
      // Pop off the last value from the substr hash
      substr_hash = prev_sdbm_hash(substr_hash, code_points[end]);
    }

    if(token_id == -1) {
      end = token_end;
      token_id = unk_token_id;

      // We need to clean up the global array. This case is very uncommon. Only 0.016% of words cannot be
      // resolved to a token from the squad dev set.
      for(uint32_t i = 1; i < num_values_tokenized; ++i) {
        token_ids[token_start + i] = std::numeric_limits<uint32_t>::max();
      }

      num_values_tokenized = 0;
    }

    token_ids[token_start + num_values_tokenized] = token_id;
    ++num_values_tokenized;
    start = end;
  }
  
  tokens_per_word[token_start] = num_values_tokenized;
}

/*
  Splits words into their token ids. 

  Some implementation details:

  Each thread is assigned a word to tokenize based on thread_to_word_map. Each thread tokenizes
  its word and writes the number of tokens it found in the tokens_per_word array. 

  The tokens_per_word array is kept to the length (num_code_points + 1). This means each thread
  can write its number of tokens to the index in thread_to_word_map corresponding to the starting
  character of each word. Since sentences must start at some word, we can prefix sum this array 
  and use the sentence_lengths code point offsets to directly index the number of tokens in each
  sentence.

  Params:
  code_points: an array containing all of the code points to be processed

  hash_table: An array containing the flattened hash table with key, value pairs packed in 64-bits

  device_bin_coefficients: A pointer to the GPU pointer containing the hashing parameters for
                           each hash bin on the GPU.
  
  device_bin_offsets: A pointer to the GPU pointer containing the start index of each bin in 
                      the flattened hash table.

  token_ids: The index for each token found during tokenization. This is of length num_code_points. 
             In most cases, multiple characters will collapse to one token. In these cases, the max
             uint32_t will be in place. Cub will be used later to filter out these invalid ids later.

             This array should be initialized to the max uint32_t before calling this kernel.

  word_starts: An array of length num_code_points. The first total word elements contains the index
               of the first character for each word.              

  word_ends: An array of length num_code_points. The first total_words elements contains the 
             past the end index for each word. This array is kept aligned with the initial token_ids
             array containing the word start code points. Thus, word_ends[word] - filtered_start_indices[word] = word_length          
  
  tokens_per_word: An array of size num_code_points that will contain the number of tokens in each 
                   word in a sentence. 
                   This array can be exclusive summed and the result used in conjunction with the sentence 
                   lengths array to find the tokens in each sentence. This is possible since the number of
                   tokens in each word will be placed at the index corresponding to the start character of 
                   a word. 
                   If we assume prefix_summed is the prefix sum of the tokens_per_word array, then 
                   prefix_summed[sentence_lengths[sentence] - 1] is the number of tokens found before the
                   start of sentence. 

  unk_token_id: The token id to be place for unknown tokens

  max_word_length: The maximum length of a word. Any word longer than this length is replaced by the unknown
                   token.
    
  total_words: The total number of white space separated words

  outer_hash_a_param: The a parameter for the outer hash

  outer_hash_b_param: The b parameter for the outer hash

  num_outer_bins: The number of bins for the outer hash
*/
__global__ void gpuWordPieceTokenizer(uint32_t* code_points, uint64_t* hash_table, uint64_t* bin_coefficients, 
                                      uint16_t* bin_offsets, uint32_t* token_ids, uint32_t* word_starts, 
                                      uint32_t* word_ends, uint8_t* tokens_per_word, uint16_t  unk_token_id, 
                                      uint16_t max_word_length, uint32_t total_words, uint32_t outer_hash_a_param, 
                                      uint32_t outer_hash_b_param, uint16_t num_outer_bins) {

  const uint32_t word_to_tokenize = blockDim.x * blockIdx.x + threadIdx.x;

  if(word_to_tokenize < total_words) {

    // Each thread gets the start code_point offset for each word and resets the token_id memory to
    // the default value. In a post processing step, all of these values will be removed.
    const uint32_t token_start = word_starts[word_to_tokenize];
    const uint32_t token_end = word_ends[word_to_tokenize];

    __wordPieceTokenize(code_points, hash_table, bin_coefficients, bin_offsets, token_ids, token_start, 
                        token_end, tokens_per_word, unk_token_id, max_word_length, outer_hash_a_param, outer_hash_b_param, 
                        num_outer_bins);
  }
}

// ---------------------------------------- Word Piece tokenizer definitions ------------------------------------------------------
// See tokenizers.cuh
GpuWordPieceTokenizer::GpuWordPieceTokenizer(std::string vocab_file, uint32_t max_num_chars, uint32_t max_inp_chars_per_word): 
device_token_ids{},
device_word_indices{},
device_tokens_per_word{},
device_hash_table{},
device_bin_coefficients{},
device_bin_offsets{} {

  transfer_hash_info_to_device(vocab_file, device_hash_table, device_bin_coefficients, device_bin_offsets,
                               unk_token_id, first_tok_id, sep_tok_id, outer_hash_a_param, outer_hash_b_param,
                               num_outer_bins);

  max_word_length = max_inp_chars_per_word;
  
  const size_t max_new_char_total = MAX_NEW_CHARS * max_num_chars;
  device_token_ids.resize(max_new_char_total);
  const size_t device_word_indices_count = 2 * max_new_char_total;
  device_word_indices.resize(device_word_indices_count);

  const size_t four_byte_cp_chunks = 1 + (max_new_char_total - 1) / sizeof(uint32_t);
  const size_t rounded_num_cps = sizeof(uint32_t) * four_byte_cp_chunks;
  device_tokens_per_word.resize(rounded_num_cps);

  // Determine temporary device storage requirements for cub
  static NotEqual select_op(std::numeric_limits<uint32_t>::max());
  size_t temp_storage_bytes = 0, temp_storage_bytes_2 = 0;
  cub::DeviceSelect::If(nullptr, temp_storage_bytes, thrust::raw_pointer_cast(device_word_indices.data()), thrust::raw_pointer_cast(device_word_indices.data()), 
                        thrust::raw_pointer_cast(device_num_selected.data()), 2*max_new_char_total, select_op);
  cub::DeviceScan::InclusiveSum(nullptr, temp_storage_bytes_2, thrust::raw_pointer_cast(device_tokens_per_word.data()), 
                        thrust::raw_pointer_cast(device_word_indices.data()), max_new_char_total);
  max_cub_storage_bytes = std::max(temp_storage_bytes, temp_storage_bytes_2);
  cub_temp_storage.resize(max_cub_storage_bytes);
  device_num_selected.resize(1);  
 }



void GpuWordPieceTokenizer::tokenize(ptr_length_pair<uint32_t*>& cp_and_length, 
                                     ptr_length_pair<uint32_t*>& offsets_and_length) {

  uint32_t* device_code_points = cp_and_length.gpu_ptr;
  size_t num_code_points = cp_and_length.length;

  uint32_t* device_sentence_offsets = offsets_and_length.gpu_ptr;
  uint32_t num_sentences = offsets_and_length.length - 1;

  // Create a selection op for all device selects                                                    
  static NotEqual select_op(std::numeric_limits<uint32_t>::max());

  // make device_start_word_indices and device_end_word_indices contiguous
  uint32_t* device_start_word_indices = thrust::raw_pointer_cast(device_word_indices.data());
  uint32_t* device_end_word_indices = device_start_word_indices + num_code_points;
  
  uint32_t total_threads = num_code_points;
  constexpr uint32_t threads_per_block = 64;
  uint32_t num_blocks = (total_threads + threads_per_block - 1) / threads_per_block;  
  init_data_and_mark_word_start_and_ends<<<num_blocks, threads_per_block>>>(device_code_points, device_start_word_indices, device_end_word_indices, 
                                                                            num_code_points, thrust::raw_pointer_cast(device_token_ids.data()), thrust::raw_pointer_cast(device_tokens_per_word.data()));
  assertCudaSuccess(cudaPeekAtLastError());  

  uint32_t word_split_blocks = (num_sentences + threads_per_block - 1) / threads_per_block;                                                              
  mark_sentence_start_and_ends<<<word_split_blocks, threads_per_block>>>(device_code_points, device_sentence_offsets, device_start_word_indices, 
                                                                         device_end_word_indices, num_sentences);
  assertCudaSuccess(cudaPeekAtLastError());  

  // Now start_word_indices has the word starts scattered throughout the array. We need to select all values not equal to the max uint32_t 
  // and place them at the start of the array. We leverage the fact that the start_word_indices and the end_word indices are contiguous to
  // only launch one device select kernel.
  cub::DeviceSelect::If(thrust::raw_pointer_cast(cub_temp_storage.data()), max_cub_storage_bytes, device_start_word_indices, device_start_word_indices, thrust::raw_pointer_cast(device_num_selected.data()), 2*num_code_points, select_op);
  assertCudaSuccess(cudaPeekAtLastError());  

  // Grab the number of words which is the number of threads needed for the main word piece tokenizer kernel. The number of tokens selected out will
  // be double the number of words since we select from both the start and end index arrays.
  uint32_t num_words = 0;
  device_num_selected.resize(1);
  assertCudaSuccess(cudaMemcpy(&num_words, thrust::raw_pointer_cast(device_num_selected.data()), sizeof(num_words), cudaMemcpyDeviceToHost));
  
  num_words /= 2;

  // We need to change the end_word_indices pointer after the selection is complete
  device_end_word_indices = device_start_word_indices + num_words;
    
  const uint32_t wp_threads_per_block = 64;
  const uint32_t num_wp_blocks = (num_words + wp_threads_per_block - 1) / wp_threads_per_block;
  gpuWordPieceTokenizer<<<num_wp_blocks, wp_threads_per_block>>>(device_code_points, thrust::raw_pointer_cast(device_hash_table.data()), thrust::raw_pointer_cast(device_bin_coefficients.data()), thrust::raw_pointer_cast(device_bin_offsets.data()), 
    thrust::raw_pointer_cast(device_token_ids.data()), device_start_word_indices, device_end_word_indices, thrust::raw_pointer_cast(device_tokens_per_word.data()), 
                                                                 unk_token_id, max_word_length, num_words, outer_hash_a_param, outer_hash_b_param, num_outer_bins);
  assertCudaSuccess(cudaPeekAtLastError());  
  
  // Repurpose the input array for the token ids. In the worst case, each code point ends up being a token so this will
  // always have enough memory to store the contiguous tokens.
  uint32_t* contiguous_token_ids = device_code_points;
  cub::DeviceSelect::If(thrust::raw_pointer_cast(cub_temp_storage.data()), max_cub_storage_bytes, thrust::raw_pointer_cast(device_token_ids.data()), contiguous_token_ids, thrust::raw_pointer_cast(device_num_selected.data()), num_code_points, select_op);
  assertCudaSuccess(cudaPeekAtLastError());  
  
  // Repurpose start word indices since it is the same size and type as the required output.
  uint32_t* token_id_counts = device_start_word_indices;
  device_start_word_indices = nullptr;
  cub::DeviceScan::InclusiveSum(thrust::raw_pointer_cast(cub_temp_storage.data()), max_cub_storage_bytes, thrust::raw_pointer_cast(device_tokens_per_word.data()), token_id_counts, num_code_points);
  assertCudaSuccess(cudaPeekAtLastError());  

  constexpr uint16_t sen_update_num_threads = 64;       
  size_t SEN_KERNEL_BLOCKS = (num_sentences + sen_update_num_threads - 1) / sen_update_num_threads;                  
  update_sentence_lengths<<<SEN_KERNEL_BLOCKS, sen_update_num_threads>>>(device_sentence_offsets, token_id_counts, num_sentences);
  assertCudaSuccess(cudaPeekAtLastError());  

  // Grab total number of token ids from the device
  uint32_t total_token_ids = 0;
  assertCudaSuccess(cudaMemcpy(&total_token_ids, token_id_counts + num_code_points - 1, sizeof(total_token_ids), cudaMemcpyDeviceToHost)); 
  
  cp_and_length.length = total_token_ids;
}



GpuWordPieceTokenizer::~GpuWordPieceTokenizer() {
}
