import torch
from PIL import Image
import mobileclip

try:
    # 1. 调用官方推荐的 API 创建模型、文本分词器及图像预处理流
    model, _, preprocess = mobileclip.create_model_and_transforms('mobileclip_s0', pretrained='../model/mobileclip/mobileclip_s0.pt')
    tokenizer = mobileclip.get_tokenizer('mobileclip_s0')
    
    # 强制切换为 CPU 推理以兼容 Windows 端侧
    model = model.eval().cpu()
    print("1. 官方模型初始化与本地权重加载成功！")

    # 2. 模拟一张实际图片和一段测试文本
    image = preprocess(Image.new('RGB', (224, 224), color='blue')).unsqueeze(0)
    text = tokenizer(["a photo of a blue background", "a photo of a red background"])
    print("2. 官方分词器与图像预处理流水线正常！")

    # 3. 前向计算多模态特征对齐
    with torch.no_grad():
        image_features = model.encode_image(image)
        text_features = model.encode_text(text)
        
        # 计算图文匹配相似度
        image_features /= image_features.norm(dim=-1, keepdim=True)
        text_features /= text_features.norm(dim=-1, keepdim=True)
        text_probs = (100.0 * image_features @ text_features.T).softmax(dim=-1)

    print(f"3. 运算成功！文本匹配概率分布: {text_probs.tolist()}")
    print("\n[ OK ] 遵循官方 ml-mobileclip 标准的多模态环境配置完全成功！")

except Exception as e:
    print(f"\n[ FAILED ] 验证失败，请检查路径或依赖。错误信息: {e}")