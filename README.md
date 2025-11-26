# RAG Local - Docker + Ollama

Système RAG (Retrieval-Augmented Generation) local et privé, conçu pour fonctionner avec Ollama sur macOS (Apple Silicon).

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MacBook M3 Pro                       │
│  ┌───────────────┐      ┌────────────────────────────┐  │
│  │    Ollama     │◄────►│      Docker Container      │  │
│  │  (natif Mac)  │ API  │  ┌──────────────────────┐  │  │
│  │               │      │  │  FastAPI + FAISS     │  │  │
│  │ - mistral     │      │  │  + LangChain         │  │  │
│  │ - nomic-embed │      │  └──────────────────────┘  │  │
│  └───────────────┘      │  ┌──────────────────────┐  │  │
│                         │  │  WebUI (Tailwind)    │  │  │
│  ┌───────────────┐      │  └──────────────────────┘  │  │
│  │  Dossier RAG/ │◄────►│         /data             │  │
│  │   (local)     │mount │                            │  │
│  └───────────────┘      └────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Prérequis

- macOS avec Apple Silicon (M1/M2/M3)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installé
- [Ollama](https://ollama.ai/) installé et fonctionnel

## Installation rapide

### 1. Installer Ollama et les modèles

```bash
# Installer Ollama (si pas déjà fait)
brew install ollama

# Démarrer Ollama
ollama serve

# Dans un autre terminal, télécharger les modèles
ollama pull mistral:latest
ollama pull nomic-embed-text
```

### 2. Cloner et lancer le projet

```bash
git clone https://github.com/votre-username/rag-local-docker.git
cd rag-local-docker

# Créer le dossier pour vos documents
mkdir -p RAG

# Lancer le conteneur
docker-compose up -d
```

### 3. Accéder à l'interface

Ouvrir http://localhost:8000 dans votre navigateur.

## Utilisation

### Ajouter des documents

Placez vos fichiers dans le dossier `RAG/` :
- PDF, TXT, MD, DOCX, EML supportés
- Les documents sont automatiquement détectés

### Interface web

1. **Onglet Documents** : Voir les fichiers disponibles, lancer l'indexation
2. **Onglet Chat** : Poser des questions sur vos documents
3. **Paramètres** : Ajuster le nombre de résultats, la température du LLM

## Configuration

Variables d'environnement (modifiables dans `docker-compose.yml`) :

| Variable | Défaut | Description |
|----------|--------|-------------|
| `OLLAMA_HOST` | `host.docker.internal:11434` | Adresse de l'API Ollama |
| `EMBEDDING_MODEL` | `nomic-embed-text` | Modèle d'embedding |
| `LLM_MODEL` | `mistral:latest` | Modèle de génération |
| `CHUNK_SIZE` | `1000` | Taille des chunks de texte |
| `CHUNK_OVERLAP` | `200` | Chevauchement entre chunks |

## Structure du projet

```
rag-local-docker/
├── docker-compose.yml    # Configuration Docker
├── Dockerfile            # Image du conteneur
├── README.md             # Cette documentation
├── RAG/                  # Vos documents (à créer)
└── app/
    ├── main.py           # API FastAPI
    ├── rag_engine.py     # Logique RAG (FAISS + LangChain)
    ├── document_loader.py # Chargement des documents
    ├── requirements.txt  # Dépendances Python
    ├── static/
    │   └── style.css     # Styles additionnels
    └── templates/
        └── index.html    # Interface web
```

## Commandes utiles

```bash
# Voir les logs
docker-compose logs -f

# Redémarrer le conteneur
docker-compose restart

# Arrêter
docker-compose down

# Reconstruire après modification
docker-compose up -d --build
```

## Dépannage

### Ollama non accessible
Vérifiez que Ollama tourne : `curl http://localhost:11434/api/tags`

### Erreur de mémoire
Réduisez `CHUNK_SIZE` dans `docker-compose.yml`

### Documents non détectés
Vérifiez les permissions du dossier `RAG/`

## Licence

MIT
