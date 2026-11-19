const hybridTimeoutMs = 5_000;
const commonWords = new Set([
  "about", "and", "are", "for", "from", "how", "into", "the",
  "this", "was", "what", "when", "where", "which", "with",
]);

function words(text) {
  return new Set(text.normalize("NFKC").toLowerCase().match(/[\p{L}\p{N}]+/gu));
}

export async function searchKnowledgePagesWithFallback(client, query) {
  try {
    const hits = await client.searchKnowledgePages(query, { timeoutMs: hybridTimeoutMs });
    return { hits };
  } catch (error) {
    if (error?.name !== "TimeoutError") throw error;
  }

  // The tree is served from Postgres and remains available while Ollama queues embeddings.
  const { items } = await client.listPages();
  const terms = [...words(query)].filter((word) => !commonWords.has(word));
  const hits = items.map(({ id, name, description }) => {
    const titleWords = words(name);
    const descriptionWords = words(description ?? "");
    const score = terms.reduce((sum, term) => (
      sum + 2 * Number(titleWords.has(term)) + Number(descriptionWords.has(term))
    ), 0);
    return { id, name, source_query: description, snippet: "", score };
  }).filter(({ score }) => score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, client.pageSearchLimit);

  return {
    hits,
    notice: "Hybrid search timed out. These results match page titles and descriptions.",
  };
}
