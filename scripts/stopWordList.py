import json
import nltk
from pathlib import Path

OUTPUT_DIR = Path(
    r"E:\all.code\Offline_Accessible_Multimodal_Local_Content_Retrieval_System"
    r"\local_retrieval_system\assets\retrieval"
)

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def save_json(file_name, words):
    words = sorted({
        str(word).strip().lower()
        for word in words
        if str(word).strip()
    })

    path = OUTPUT_DIR / file_name

    with open(path, "w", encoding="utf-8") as f:
        json.dump(
            words,
            f,
            ensure_ascii=False,
            indent=2,
        )

    print(f"{file_name}: {len(words)} words")
    print(f"Saved to: {path}")


# Download NLTK stopwords corpus
nltk.download("stopwords")

from nltk.corpus import stopwords

english_words = stopwords.words("english")

save_json(
    "stopwords_en.json",
    english_words,
)

print()
print("Done.")