enum SupportedType {txt, pdf, docx, image, unknown}

class ParserFactory {
  static SupportedType getFileType(String filePath){
    final pathLower = filePath.toLowerCase();
    if(pathLower.endsWith('.txt')) return SupportedType.txt;
    if(pathLower.endsWith('.pdf')) return SupportedType.pdf;
    if(pathLower.endsWith('.docx')) return SupportedType.docx;
    if(pathLower.endsWith('.jpg') || pathLower.endsWith('.png')) return SupportedType.image;
    return SupportedType.unknown;
  }
}