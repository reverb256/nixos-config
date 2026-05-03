
int32_t llama_triattention_init(
        struct llama_context * ctx,
                  const char * stats_path,
                     int32_t   budget,
                     int32_t   divide_length,
                     int32_t   offset_max,
                     int32_t   mode,
                     int32_t   trigger,
                     int32_t   agg,
                     int32_t   seed,
                        bool   normalize_scores,
                        bool   protect_prefill,
                        bool   disable_mlr,
                        bool   disable_trig,
                        bool   enable_logging) {
    if (!ctx || !stats_path || stats_path[0] == '\0') {
        return -1;
    }

    auto * mem = ctx->get_memory();
    if (!mem) {
        LLAMA_LOG_ERROR("%s: context has no memory\n", __func__);
        return -1;
    }

    auto * kv = dynamic_cast<llama_kv_cache *>(mem);
    if (!kv) {
        auto * mem_hybrid = dynamic_cast<llama_memory_hybrid *>(mem);
        if (mem_hybrid) {
            kv = mem_hybrid->get_mem_attn();
        }
    }
    if (!kv) {
        LLAMA_LOG_ERROR("%s: memory is not a KV cache (recurrent models not supported)\n", __func__);
        return -1;
    }

    triattention_config cfg = {};
    cfg.budget           = (uint32_t)budget;
    cfg.divide_length    = (uint32_t)divide_length;
    cfg.offset_max       = (uint32_t)offset_max;
    cfg.mode             = (triattention_mode)mode;
    cfg.trigger          = (triattention_trigger)trigger;
    cfg.agg              = (triattention_agg)agg;
    cfg.seed             = seed;
    cfg.normalize_scores = normalize_scores;
    cfg.protect_prefill  = protect_prefill;
    cfg.disable_mlr      = disable_mlr;
    cfg.disable_trig     = disable_trig;
    cfg.enable_logging   = enable_logging;

    kv->init_triattention(stats_path, &cfg);
    return kv->has_triattention() ? 0 : -1;
}
