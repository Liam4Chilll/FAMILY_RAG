"""Chargement et parsing des documents multi-formats."""

import os
import email
import chardet
from pathlib import Path
from typing import List, Optional
from dataclasses import dataclass

from langchain.schema import Document
from pypdf import PdfReader
from docx import Document as DocxDocument
import pytesseract
from PIL import Image

from config import get_settings


@dataclass
class LoadedDocument:
    """Document chargé avec métadonnées."""
    filename: str
    content: str
    file_type: str
    size_bytes: int
    error: Optional[str] = None


class DocumentLoader:
    """Chargeur de documents multi-formats."""
    
    SUPPORTED_EXTENSIONS = {'.pdf', '.txt', '.md', '.docx', '.eml', '.jpg', '.jpeg', '.png'}
    
    def __init__(self):
        self.settings = get_settings()
        self.data_dir = Path(self.settings.data_dir)
    
    def list_files(self) -> List[dict]:
        """Liste tous les fichiers supportés dans le dossier data."""
        files = []
        if not self.data_dir.exists():
            return files
        
        for file_path in self.data_dir.rglob('*'):
            if file_path.is_file() and file_path.suffix.lower() in self.SUPPORTED_EXTENSIONS:
                files.append({
                    'name': file_path.name,
                    'path': str(file_path.relative_to(self.data_dir)),
                    'type': file_path.suffix.lower()[1:],
                    'size': file_path.stat().st_size
                })
        
        return sorted(files, key=lambda x: x['name'].lower())
    
    def load_all(self) -> List[Document]:
        """Charge tous les documents du dossier data."""
        documents = []
        
        for file_info in self.list_files():
            file_path = self.data_dir / file_info['path']
            loaded = self._load_file(file_path)
            
            if loaded.content and not loaded.error:
                doc = Document(
                    page_content=loaded.content,
                    metadata={
                        'source': loaded.filename,
                        'file_type': loaded.file_type,
                        'size_bytes': loaded.size_bytes
                    }
                )
                documents.append(doc)
        
        return documents
    
    def _load_file(self, file_path: Path) -> LoadedDocument:
        """Charge un fichier selon son extension."""
        ext = file_path.suffix.lower()
        size = file_path.stat().st_size
        
        try:
            if ext == '.pdf':
                content = self._load_pdf(file_path)
            elif ext in {'.txt', '.md'}:
                content = self._load_text(file_path)
            elif ext == '.docx':
                content = self._load_docx(file_path)
            elif ext == '.eml':
                content = self._load_eml(file_path)
            elif ext in {'.jpg', '.jpeg', '.png'}:
                content = self._load_image(file_path)
            else:
                return LoadedDocument(
                    filename=file_path.name,
                    content='',
                    file_type=ext[1:],
                    size_bytes=size,
                    error=f'Extension non supportée: {ext}'
                )
            
            return LoadedDocument(
                filename=file_path.name,
                content=content,
                file_type=ext[1:],
                size_bytes=size
            )
            
        except Exception as e:
            return LoadedDocument(
                filename=file_path.name,
                content='',
                file_type=ext[1:],
                size_bytes=size,
                error=str(e)
            )
    
    def _load_pdf(self, file_path: Path) -> str:
        """Extrait le texte d'un PDF."""
        reader = PdfReader(file_path)
        texts = []
        for page in reader.pages:
            text = page.extract_text()
            if text:
                texts.append(text)
        return '\n\n'.join(texts)
    
    def _load_text(self, file_path: Path) -> str:
        """Charge un fichier texte avec détection d'encodage."""
        raw = file_path.read_bytes()
        detected = chardet.detect(raw)
        encoding = detected.get('encoding', 'utf-8') or 'utf-8'
        return raw.decode(encoding, errors='replace')
    
    def _load_docx(self, file_path: Path) -> str:
        """Extrait le texte d'un fichier Word."""
        doc = DocxDocument(file_path)
        paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
        return '\n\n'.join(paragraphs)
    
    def _load_eml(self, file_path: Path) -> str:
        """Extrait le contenu d'un email."""
        raw = file_path.read_bytes()
        msg = email.message_from_bytes(raw)
        
        parts = []
        
        # En-têtes
        if msg['subject']:
            parts.append(f"Sujet: {msg['subject']}")
        if msg['from']:
            parts.append(f"De: {msg['from']}")
        if msg['to']:
            parts.append(f"À: {msg['to']}")
        if msg['date']:
            parts.append(f"Date: {msg['date']}")
        
        parts.append('')  # Ligne vide
        
        # Corps
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == 'text/plain':
                    payload = part.get_payload(decode=True)
                    if payload:
                        charset = part.get_content_charset() or 'utf-8'
                        parts.append(payload.decode(charset, errors='replace'))
        else:
            payload = msg.get_payload(decode=True)
            if payload:
                charset = msg.get_content_charset() or 'utf-8'
                parts.append(payload.decode(charset, errors='replace'))
        
        return '\n'.join(parts)
    
    def _load_image(self, file_path: Path) -> str:
        """Extrait le texte d'une image via OCR (Tesseract)."""
        image = Image.open(file_path)
        # Utilise français + anglais pour la reconnaissance
        text = pytesseract.image_to_string(image, lang='fra+eng')
        return text.strip()
