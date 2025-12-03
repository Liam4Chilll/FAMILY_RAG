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
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License"/>
</p>

---

<h1 align="center">📚 FamilyRAG 2.5.0</h1>

<h3 align="center">
  <em>Votre bibliothèque numérique privée</em>
</h3>

<p align="center">
  Posez des questions à vos documents en langage naturel.<br/>
  Sans cloud. Sans abonnement. Sans compromis sur la vie privée.
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

## ✨ Nouveautés v2.5

### 📎 Upload d'images dans le chat
- Glissez-déposez une image directement dans le chat
- Ou cliquez sur 📎 pour sélectionner un fichier
- Analyse vision immédiate via Ministral 3
- Preview de l'image dans la conversation

### ⏹ Bouton Stop
- Interrompez une génération trop longue
- Feedback visuel immédiat

### 🎭 Arrière-plan immersif
- Formes géométriques flottantes en filigrane
- Animation fluide avec rebond aux bords
- S'adapte au thème choisi
- Ambiance "bibliothèque numérique"

### 🎨 6 Thèmes UI
- **Dark Pro** — Bleu acier, sobre et professionnel
- **Ocean** — Cyan profond, frais et tech
- **Forest** — Vert émeraude, nature et calme
- **Amber** — Orange chaud, chaleureux
- **Mono** — Noir/blanc pur, minimaliste
- **Family** — Violet original

### 🔧 Améliorations
- Détection automatique des modèles vision
- Persistance du thème choisi
- Interface plus légère et réactive

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

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      MacBook (Apple Silicon)                    │
│                                                                 │
│  ┌─────────────────┐        ┌────────────────────────────────┐  │
│  │     Ollama      │◄──────►│     Docker Container           │  │
│  │   (natif Mac)   │  API   │                                │  │
│  │                 │        │  ┌──────────────────────────┐  │  │
│  │ • ministral-3   │        │  │  FastAPI + FAISS         │  │  │
│  │ • nomic-embed   │        │  │  + LangChain + Tesseract │  │  │
│  │                 │        │  └──────────────────────────┘  │  │
│  └─────────────────┘        │                                │  │
│          │                  │  ┌──────────────────────────┐  │  │
│          │ GPU              │  │  WebUI (6 thèmes)        │  │  │
│          ▼                  │  │  Tailwind + Alpine       │  │  │
│  ┌─────────────────┐        │  └──────────────────────────┘  │  │
│  │  Apple Silicon  │        │                                │  │
│  │   M1/M2/M3      │        │        localhost:8000          │  │
│  └─────────────────┘        └────────────────────────────────┘  │
│                                        ▲                        │
│  ┌─────────────────┐                   │                        │
│  │  📁 Vos Docs    │───────────────────┘                        │
│  │  (RAG folder)   │  volume mount                              │
│  └─────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Prérequis

- **Ollama 0.13.1+** (requis pour Ministral 3)
- Docker Desktop

```bash
# Vérifier la version Ollama
ollama --version
```

---

## Installation

### 1. Installer les modèles Ollama

```bash
# Modèle de génération + vision (recommandé)
ollama pull ministral-3:latest

# Ou autres modèles de génération
ollama pull qwen2.5:7b
ollama pull mistral:latest

# Modèle d'embedding (obligatoire)
ollama pull nomic-embed-text
```

### 2. Configurer le projet

```bash
cd /chemin/vers/family-rag

# Créer le dossier documents
mkdir -p RAG

# Placer vos fichiers dans RAG/
```

### 3. Lancer

```bash
docker-compose up -d --build
```

### 4. C'est prêt !

Ouvrez **http://localhost:8000** 🎉

---

## 📖 Documentation

Consultez le **[Guide d'Administration](MANAGE.md)** pour la maintenance et le dépannage.

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
