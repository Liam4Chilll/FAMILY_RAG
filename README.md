<p align="center">
  <img src="https://img.shields.io/badge/Python-3.11-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python"/>
  <img src="https://img.shields.io/badge/FastAPI-0.115-009688?style=for-the-badge&logo=fastapi&logoColor=white" alt="FastAPI"/>
  <img src="https://img.shields.io/badge/Docker-24.0-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker"/>
  <img src="https://img.shields.io/badge/Ollama-LLM-000000?style=for-the-badge&logo=ollama&logoColor=white" alt="Ollama"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/LangChain-0.3-1C3C3C?style=for-the-badge&logo=langchain&logoColor=white" alt="LangChain"/>
  <img src="https://img.shields.io/badge/FAISS-Vector_DB-0467DF?style=for-the-badge&logo=meta&logoColor=white" alt="FAISS"/>
  <img src="https://img.shields.io/badge/Tailwind_CSS-3.x-06B6D4?style=for-the-badge&logo=tailwindcss&logoColor=white" alt="Tailwind"/>
  <img src="https://img.shields.io/badge/Alpine.js-3.x-8BC0D0?style=for-the-badge&logo=alpine.js&logoColor=white" alt="Alpine.js"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Apple_Silicon-M1%2FM2%2FM3-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Apple Silicon"/>
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License"/>
</p>

---

<h1 align="center">📚 FamilyRAG 2.1.0</h1>

<h3 align="center">
  <em>Votre bibliothèque interactive intergénérationnelle, 100% locale</em>
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
- 📝 Les cours et devoirs des enfants
- 📧 Les archives emails importantes
- 📚 Votre bibliothèque personnelle de livres et articles

**Le tout sans qu'une seule donnée ne quitte votre domicile.**

---

## ✨ Pourquoi FamilyRAG ?

<table>
<tr>
<td width="50%">

### 🔒 Souveraineté totale
Vos documents restent sur **votre** machine. Aucun serveur distant, aucun cloud, aucune fuite de données possible.

### 🌐 100% Hors-ligne
Une fois installé, FamilyRAG fonctionne **sans connexion internet**. Idéal pour les zones rurales ou les familles soucieuses de leur empreinte numérique.

</td>
<td width="50%">

### 👨‍👩‍👧‍👦 Intergénérationnel
Une interface simple et intuitive, accessible aux grands-parents comme aux adolescents. Posez vos questions naturellement, obtenez des réponses claires.

### ⚡ Performant
Optimisé pour Apple Silicon (M1/M2/M3), FamilyRAG exploite la puissance de votre Mac pour des réponses rapides et pertinentes.

</td>
</tr>
</table>

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      MacBook (Apple Silicon)                │
│                                                             │
│  ┌─────────────────┐        ┌────────────────────────────┐  │
│  │     Ollama      │◄──────►│     Docker Container       │  │
│  │   (natif Mac)   │  API   │                            │  │
│  │                 │        │  ┌──────────────────────┐  │  │
│  │ • mistral       │        │  │  FastAPI + FAISS     │  │  │
│  │ • nomic-embed   │        │  │  + LangChain         │  │  │
│  │                 │        │  └──────────────────────┘  │  │
│  └─────────────────┘        │                            │  │
│          │                  │  ┌──────────────────────┐  │  │
│          │ GPU              │  │  WebUI               │  │  │
│          ▼                  │  │  Tailwind + Alpine   │  │  │
│  ┌─────────────────┐        │  └──────────────────────┘  │  │
│  │  Apple Silicon  │        │                            │  │
│  │   M1/M2/M3      │        │        localhost:8000      │  │
│  └─────────────────┘        └────────────────────────────┘  │
│                                        ▲                    │
│  ┌─────────────────┐                   │                    │
│  │  📁 Vos Docs    │───────────────────┘                    │
│  │  (RAG folder)   │  volume mount                          │
│  └─────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Installation

### 1. Installer les modèles Ollama

```bash
# Modèle de génération (choisir un ou plusieurs)
ollama pull qwen2.5:7b
ollama pull mistral:latest

# Modèle d'embedding (obligatoire)
ollama pull nomic-embed-text
```

### 2. Configurer le projet

```bash
# Cloner ou télécharger le projet
cd /chemin/vers/family-rag

# Créer le dossier pour vos documents
mkdir -p RAG

# Placer vos documents dans RAG/
# Formats supportés : PDF, TXT, MD, DOCX, EML
```

### 3. (Optionnel) Configurer le chemin des documents

Par défaut, le dossier `./RAG` est utilisé. Pour un chemin personnalisé, éditez `docker-compose.yml` :

```
```yaml
volumes:
  - /chemin/absolu/vers/vos/documents:/data
```

## Utilisation

### Lancer le service

```bash
# Premier lancement (build + démarrage)
docker-compose up -d --build

# Lancements suivants
docker-compose up -d
```

### Étape 4 — Lancer FamilyRAG

```bash
docker-compose up -d --build
```

### Étape 5 — C'est prêt !

Ouvrez **http://localhost:8000** et commencez à interroger vos documents. 🎉

---

## 📂 Formats supportés

<p align="center">
  <img src="https://img.shields.io/badge/PDF-Documents-EC1C24?style=for-the-badge&logo=adobe-acrobat-reader&logoColor=white" alt="PDF"/>
  <img src="https://img.shields.io/badge/TXT-Texte-4A4A4A?style=for-the-badge&logo=textpattern&logoColor=white" alt="TXT"/>
  <img src="https://img.shields.io/badge/MD-Markdown-000000?style=for-the-badge&logo=markdown&logoColor=white" alt="MD"/>
  <img src="https://img.shields.io/badge/DOCX-Word-2B579A?style=for-the-badge&logo=microsoft-word&logoColor=white" alt="DOCX"/>
  <img src="https://img.shields.io/badge/EML-Email-005FF9?style=for-the-badge&logo=mail.ru&logoColor=white" alt="EML"/>
</p>

---

## 📖 Documentation

Pour l'administration, la configuration avancée et le dépannage, consultez le **[Guide d'Administration](MANAGE.md)**.

---

## 📜 Licence

Ce projet est distribué sous licence **MIT**. Utilisez-le, modifiez-le, partagez-le librement.

---

<p align="center">
  <strong>Construit avec ❤️ par <a href="https://github.com/Liam4Chilll">Liam4Chilll</a></strong>
</p>

<p align="center">
  <em>FamilyRAG — Parce que vos données familiales méritent de rester en famille.</em>
</p>
