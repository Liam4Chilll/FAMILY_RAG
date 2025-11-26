# Guide d'Administration - RAG Local

## Commandes essentielles

### Gestion du conteneur

```bash
# Démarrer
docker-compose up -d

# Arrêter
docker-compose down

# Redémarrer
docker-compose restart

# Voir les logs en temps réel
docker logs -f rag-local

# Voir les dernières 100 lignes
docker logs --tail 100 rag-local
```

### Rebuild complet (après modification du code)

```bash
docker-compose down
docker rmi files-rag:latest
docker-compose up -d --build
```

### Accès au conteneur

```bash
# Shell interactif
docker exec -it rag-local /bin/bash

# Exécuter une commande
docker exec rag-local ls -la /app
docker exec rag-local ls -la /data
```

---

## Gestion Ollama (sur macOS)

### Démarrage

```bash
# Démarrer le service
ollama serve

# Vérifier que Ollama répond
curl http://localhost:11434/api/tags
```

### Modèles

```bash
# Lister les modèles installés
ollama list

# Télécharger les modèles requis
ollama pull mistral:latest
ollama pull nomic-embed-text

# Supprimer un modèle
ollama rm nom-du-modele

# Tester un modèle
ollama run mistral:latest "Bonjour, ça fonctionne ?"
```

---

## Vérifications

### Health check

```bash
# API RAG
curl http://localhost:8000/health

# Réponse attendue :
# {"status":"healthy","ollama_connected":true,"ollama_host":"host.docker.internal:11434"}
```

### Endpoints API

| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/` | GET | Interface web |
| `/health` | GET | État du service |
| `/api/files` | GET | Liste des fichiers |
| `/api/index` | POST | Lancer l'indexation |
| `/api/query` | POST | Poser une question |
| `/api/stats` | GET | Statistiques |
| `/api/settings` | PUT | Modifier paramètres |
| `/api/ollama/models` | GET | Modèles Ollama |

### Test rapide de l'API

```bash
# Lister les fichiers
curl http://localhost:8000/api/files

# Indexer
curl -X POST http://localhost:8000/api/index

# Poser une question
curl -X POST http://localhost:8000/api/query \
  -H "Content-Type: application/json" \
  -d '{"question": "De quoi parlent les documents ?"}'
```

---

## Volumes et données

### Emplacement des données

| Donnée | Conteneur | Hôte |
|--------|-----------|------|
| Documents | `/data` | `./RAG/` |
| Index FAISS | `/app/index` | Volume Docker `rag-local-index` |

### Gestion de l'index

```bash
# Voir le volume
docker volume inspect rag-local-index

# Supprimer l'index (force réindexation)
docker volume rm rag-local-index

# Backup de l'index
docker cp rag-local:/app/index ./backup-index
```

### Ajouter des documents

```bash
# Copier des fichiers dans le dossier RAG
cp mon-document.pdf ./RAG/
cp -r mon-dossier/*.txt ./RAG/

# Les fichiers sont immédiatement visibles dans l'interface
# Cliquer sur "Indexer les documents" pour les intégrer
```

---

## Configuration

### Variables d'environnement (docker-compose.yml)

```yaml
environment:
  - OLLAMA_HOST=host.docker.internal:11434  # Adresse Ollama
  - EMBEDDING_MODEL=nomic-embed-text        # Modèle d'embedding
  - LLM_MODEL=mistral:latest                # Modèle LLM
  - CHUNK_SIZE=1000                         # Taille des chunks
  - CHUNK_OVERLAP=200                       # Chevauchement
```

### Modifier la configuration

1. Éditer `docker-compose.yml`
2. Relancer : `docker-compose up -d`

---

## Dépannage

### Le conteneur ne démarre pas

```bash
# Voir les logs détaillés
docker-compose logs

# Vérifier l'état
docker ps -a
```

### Ollama non connecté (point rouge dans l'UI)

```bash
# Vérifier qu'Ollama tourne
curl http://localhost:11434/api/tags

# Si erreur, démarrer Ollama
ollama serve
```

### Erreur d'indexation

```bash
# Vérifier les permissions du dossier RAG
ls -la RAG/

# Vérifier que les fichiers sont lisibles
file RAG/*
```

### Réponses lentes

- Réduire `top_k` dans les paramètres (moins de chunks = plus rapide)
- Réduire `CHUNK_SIZE` dans docker-compose.yml
- Vérifier la charge CPU/RAM

### Reset complet

```bash
# Tout supprimer et repartir de zéro
docker-compose down -v
docker rmi files-rag:latest
docker-compose up -d --build
```

---

## Mise à jour

### Mettre à jour le code

```bash
git pull
docker-compose down
docker-compose up -d --build
```

### Mettre à jour les modèles Ollama

```bash
ollama pull mistral:latest
ollama pull nomic-embed-text
```

---

## Ressources

- **Interface web** : http://localhost:8000
- **API docs** : http://localhost:8000/docs (Swagger auto-généré)
- **Ollama** : http://localhost:11434
