<p align="center">
  <img src="https://img.shields.io/badge/Python-3.11-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python"/>
  <img src="https://img.shields.io/badge/FastAPI-0.115-009688?style=for-the-badge&logo=fastapi&logoColor=white" alt="FastAPI"/>
  <img src="https://img.shields.io/badge/Docker-24.0-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker"/>
  <img src="https://img.shields.io/badge/Ollama-0.13+-000000?style=for-the-badge&logo=ollama&logoColor=white" alt="Ollama"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/LangChain-0.3-1C3C3C?style=for-the-badge&logo=langchain&logoColor=white" alt="LangChain"/>
  <img src="https://img.shields.io/badge/FAISS-Vector_DB-0467DF?style=for-the-badge&logo=meta&logoColor=white" alt="FAISS"/>
  <img src="https://img.shields.io/badge/Ministral_3-Vision-FF6B6B?style=for-the-badge&logo=mistral&logoColor=white" alt="Ministral 3"/>
  <img src="https://img.shields.io/badge/Tesseract-OCR-5A5A5A?style=for-the-badge&logo=google&logoColor=white" alt="Tesseract"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Apple_Silicon-M1%2FM2%2FM3-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Apple Silicon"/>
  <img src="https://img.shields.io/badge/Linux-Serveur-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux"/>
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License"/>
</p>

---

<h1 align="center">📚 FamilyRAG 2.7</h1>

<h3 align="center">
  <em>Votre bibliothèque numérique privée — maintenant accessible partout dans votre réseau</em>
</h3>

<p align="center">
  Posez des questions à vos documents en langage naturel.<br/>
  Sans cloud. Sans abonnement. Sans compromis sur la vie privée.<br/>
</p>

---

## 🏠 Qu'est-ce que FamilyRAG ?

**FamilyRAG** est un système RAG (Retrieval-Augmented Generation) entièrement local, conçu pour les familles qui souhaitent exploiter la puissance de l'IA générative tout en gardant le contrôle total sur leurs données.

Imaginez pouvoir interroger en langage naturel :
- 📄 Les documents administratifs de la famille
- 📖 Les recettes de grand-mère numérisées
- 🖼️ Les photos de documents et textes scannés (OCR + Vision IA)
- 📝 Les cours et devoirs des enfants
- 📧 Les archives emails importantes
- 📚 Votre bibliothèque personnelle de livres et articles

**Le tout sans qu'une seule donnée ne quitte votre domicile.**

---

## ✨ Nouveautés v2.7

### 🐧 Support Linux complet — Déploiement serveur

La v2.7 marque une évolution majeure : **FamilyRAG devient un serveur accessible depuis tout votre réseau local** !

- **Déploiement sur VM/serveur Linux** — Documentation complète avec guide pas à pas
- **Auto-détection intelligente d'Ollama** — Trouve automatiquement Ollama (Mac, Windows, Linux)
- **Accès réseau centralisé** — Un seul serveur, accessible depuis tous vos appareils (PC, Mac, mobile)
- **Configuration simplifiée** — Plus besoin de manipulation complexe, tout est automatique
- **Fichier de config Ollama inclus** — `ollama-override.conf` prêt à l'emploi pour Linux

### 📊 Monitoring système en temps réel

- **Dashboard métriques** — CPU, RAM, disque affichés dans l'interface
- **Endpoint API dédié** — `/api/system/metrics` pour surveiller les ressources
- **Alertes visuelles** — Indicateurs de santé système en direct

### 🎯 Indexation et recherche améliorées

- **Indexation sélective** — Choisissez précisément les fichiers à indexer
- **Filtrage par sources** — Limitez la recherche à des documents spécifiques
- **Re-ranking optionnel** — Activez/désactivez le re-ranking selon vos besoins
- **Détails d'index enrichis** — Visualisez exactement quels fichiers sont indexés

### 🔧 Robustesse et fiabilité

- **Gestion d'erreur améliorée** — Messages clairs en cas de problème
- **Vérification automatique des chunks** — Prévient les dépassements de limite d'embedding
- **Détection multi-environnement** — Fonctionne sur Mac, Windows, Linux sans config manuelle

---

## 🎊 Rappel des bénéfices v2.6 — La révolution RAG

La v2.6 avait déjà apporté une **refonte majeure du pipeline de recherche** :

### 🎯 Précision RAG +65%

- **Re-ranking LLM** — Chaque chunk est réévalué sémantiquement par le LLM, éliminant les faux positifs
- **Métadonnées enrichies** — Date, année, type de document et auteur extraits automatiquement
- **Chunking intelligent** — Préserve la structure (articles, listes, tableaux) au lieu de couper arbitrairement
- **Citations obligatoires** — Chaque réponse cite ses sources `[document.pdf]`

### 🔧 Contrôle total depuis l'interface

- **Sélection du modèle LLM** — Changez de modèle en un clic, sans redémarrage
- **Sélection du modèle d'embedding** — Passez de `nomic-embed-text` à `mxbai-embed-large` instantanément
- **Debug chunks** — Visualisez exactement quels passages ont été récupérés et leur score

### 💬 Historique des conversations

- Sidebar avec toutes vos conversations
- Reprenez une discussion là où vous l'avez laissée
- Sélection de sources par conversation

### 🎨 3 Thèmes UI

- **Midnight** — Bleu acier, sobre et professionnel
- **Cyber** — Cyan néon, ambiance tech
- **Tactical** — Vert militaire, rouge accent

---

## 📊 Gains de précision v2.5 → v2.6

| Métrique | v2.5 | v2.6 |
|----------|------|------|
| Chunks récupérés | 4 | 12 |
| Réponses avec citations | ~30% | ~85% |
| Faux positifs | ~40% | ~10% |
| **Précision globale** | **~45%** | **~75%** |

---

## 🗂️ Formats supportés

<p align="center">
  <img src="https://img.shields.io/badge/PDF-Documents-EC1C24?style=for-the-badge&logo=adobe-acrobat-reader&logoColor=white" alt="PDF"/>
  <img src="https://img.shields.io/badge/TXT-Texte-4A4A4A?style=for-the-badge&logo=textpattern&logoColor=white" alt="TXT"/>
  <img src="https://img.shields.io/badge/MD-Markdown-000000?style=for-the-badge&logo=markdown&logoColor=white" alt="MD"/>
  <img src="https://img.shields.io/badge/DOCX-Word-2B579A?style=for-the-badge&logo=microsoft-word&logoColor=white" alt="DOCX"/>
  <img src="https://img.shields.io/badge/EML-Email-005FF9?style=for-the-badge&logo=mail.ru&logoColor=white" alt="EML"/>
  <img src="https://img.shields.io/badge/JPG-Image-FFD700?style=for-the-badge&logo=image&logoColor=black" alt="JPG"/>
  <img src="https://img.shields.io/badge/PNG-Image-FFD700?style=for-the-badge&logo=image&logoColor=black" alt="PNG"/>
</p>

**Images** : OCR Tesseract (indexation) + Vision Ministral 3 (analyse à la demande)

---

## 🏗️ Architecture v2.7

```
┌─────────────────────────────────────────────────────────────────┐
│               Réseau Local (192.168.x.x)                        │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │  MacBook     │   │  PC Windows  │   │  Mobile      │        │
│  │  Safari      │   │  Chrome      │   │  Safari      │        │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘        │
│         │                  │                  │                │
│         └──────────────────┼──────────────────┘                │
│                            │                                   │
│                            ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         Serveur Linux (VM / Machine dédiée)             │   │
│  │                                                         │   │
│  │  ┌─────────────────┐        ┌─────────────────────┐    │   │
│  │  │     Ollama      │◄──────►│  Docker Container   │    │   │
│  │  │   (natif Linux) │  API   │                     │    │   │
│  │  │                 │        │  ┌───────────────┐  │    │   │
│  │  │ • ministral-3   │        │  │  FastAPI      │  │    │   │
│  │  │ • nomic-embed   │        │  │  + FAISS      │  │    │   │
│  │  │ • mistral       │        │  │  + LangChain  │  │    │   │
│  │  └─────────────────┘        │  │  + Tesseract  │  │    │   │
│  │          │                  │  └───────────────┘  │    │   │
│  │          │ GPU/CPU          │                     │    │   │
│  │          ▼                  │  ┌───────────────┐  │    │   │
│  │  ┌─────────────────┐        │  │  WebUI        │  │    │   │
│  │  │  CPU/RAM/Disque │        │  │  3 thèmes     │  │    │   │
│  │  │  (Monitoring)   │        │  │  + Metrics    │  │    │   │
│  │  └─────────────────┘        │  └───────────────┘  │    │   │
│  │                             │                     │    │   │
│  │  ┌─────────────────┐        │  http://IP:8000     │    │   │
│  │  │  📁 Vos Docs    │────────┴─────────────────────┘    │   │
│  │  │  (RAG folder)   │    volume mount                   │   │
│  │  └─────────────────┘                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Installation

### Mac / Windows (Docker Desktop)

#### 1. Prérequis

- **Ollama 0.13.1+** (requis pour Ministral 3)
- Docker Desktop

```bash
# Vérifier la version Ollama
ollama --version
```

#### 2. Cloner et configurer

```bash
git clone https://github.com/Liam4Chilll/family-rag.git
cd family-rag
cp .env.example .env
```

Éditer `.env` pour définir le chemin vers vos documents :

```bash
nano .env
# Modifier HOST_DATA_PATH=/chemin/vers/vos/documents
```

#### 3. Installer les modèles Ollama

```bash
# Modèle de génération + vision (recommandé)
ollama pull ministral-3:latest

# Ou autres modèles de génération
ollama pull qwen2.5:7b
ollama pull mistral:latest

# Modèle d'embedding (obligatoire)
ollama pull nomic-embed-text
```

#### 4. Lancer

```bash
docker compose up -d --build
```

#### 5. C'est prêt !

Ouvrez **http://localhost:8000** 🎉

**Avantages du déploiement serveur** :
- ✅ **Une seule instance** pour toute la famille
- ✅ **Accès depuis n'importe quel appareil** du réseau local
- ✅ **Ressources mutualisées** (pas besoin de GPU sur chaque machine)
- ✅ **Données centralisées** et toujours disponibles

---

## 📖 Documentation

| Guide | Description |
|-------|-------------|
| [Administration](/MANAGE.md) | Gestion, diagnostic et maintenance |
| [Changelog](https://github.com/Liam4Chilll/FAMILY_RAG/releases) | Historique complet des versions |

---

## 🎯 Cas d'usage

### Mode Standalone (Mac/Windows)
- Utilisation personnelle sur votre ordinateur
- Données locales, aucun réseau requis
- Idéal pour tester ou usage nomade

### Mode Serveur (Linux)
- Serveur central accessible par toute la famille
- Mutualisation des ressources (CPU, RAM, stockage)
- Accès depuis n'importe quel appareil (PC, Mac, mobile)
- Idéal pour un NAS, une VM ou un serveur domestique

---

## 🔒 Sécurité et confidentialité

- **100% local** — Aucune donnée n'est envoyée à des serveurs externes
- **Pas de télémétrie** — Aucun tracking, aucune statistique collectée
- **Accès réseau local uniquement** — Non exposé sur Internet par défaut
- **Données chiffrées** — Utilisez le chiffrement de votre OS/NAS pour les documents sensibles
- **Open Source** — Code auditable, licence MIT

---

## 📜 Licence

Ce projet est distribué sous licence **MIT**.

---

<p align="center">
  <strong>Construit avec ❤️ par <a href="https://github.com/Liam4Chilll">Liam4Chilll</a></strong>
</p>

<p align="center">
  <em>FamilyRAG — Parce que vos données familiales méritent de rester en famille.</em>
</p>
