# 基于神经网络捏脸


## VERSION

```
1. Unity2019.2.1f1
2. python-2.7
3. tensorflow-1.1
4. dlib-19.18
5. numpy-1.15.4
6. opencv-contrib-python 3.4.0.12
7. tqdm-4.23.4
```


## 论文

网易伏羲实验室、密歇根大学、北航和浙大的研究者提出了一种游戏角色自动创建方法，利用 Face-to-Parameter 的转换快速创建游戏角色，用户还可以自行基于模型结果再次进行修改，直到得到自己满意的人物。此项目按照[论文][i2]里的描述建立。

![](/image/t2.jpeg)


## 引擎预览

打开Unity, 点击菜单栏Tools->Preview, 通过此工具可以手动去捏脸。

![](/image/t1.jpg)


## Database

打开Unity, 点击菜单栏Tools->GenerateDatabase

这里由引擎随机生成2000张图片， 其中80%用作训练集， 20%用作验证集。同时在图片同目录会生成二进制文件db_description，记录捏脸相关的参数。

生成图片分辨率：512x512, 生成目录在unity项目同级目录export/database文件夹里， 于论文里不同的是这里使用Unity引擎代替Justice引擎。


## 脸部对齐 - Face alignment

对于输入图片，通过此工具dlib进行脸部截取。

```
pip install dlib
```

dlib 引用模型下载地址:

http://dlib.net/files/shape_predictor_68_face_landmarks.dat.bz2 

http://dlib.net/files/dlib_face_recognition_resnet_model_v1.dat.bz2

##  LightCNN

[light_cnn][i5]出自2016 cvpr吴翔A Light CNN for Deep Face Representation with Noisy Labels，论文里使用LightCNN用于Loss函数L1, 衡量引擎生成的图片和Imitator生成的图片差异。

light_cnn优势在于一个很小的模型和一个非常不错的识别率。主要原因在于，

（1）作者使用maxout作为激活函数，实现了对噪声的过滤和对有用信号的保留，从而产生更好的特征图MFM(Max-Feature-Map)。这个思想非常不错，本人将此思想用在center_loss中，实现了大概0.5%的性能提升，同时，这个maxout也就是所谓的slice+eltwise，这2个层的好处就是，一，不会产生训练的参数，二，基本很少耗时，给人的感觉就是不做白不做，性能还有提升。

（2）作者使用了NIN(Network inNetwork)来减少参数，并提升效果，作者提供的A模型是没有NIN操作的，B模型是有NIN操作的，2个模型的训练数据集都是CASIA，但是性能有0.5%的提升，当然代价是会有额外参数的产生。但是相比其他网络结构，使用NIN还是会使模型小不少，作者论文中的网络结构和B,C模型相对应。

[the model of LightCNN-29 v2][i6]



[i1]: https://xueqiu.com/9217191040/133506937
[i2]: https://arxiv.org/abs/1909.01064
[i3]: http://www.sohu.com/a/339985351_823210
[i4]: https://blog.csdn.net/qiumokucao/article/details/81610628
[i5]: https://github.com/AlfredXiangWu/LightCNN
[i6]: https://drive.google.com/open?id=1Jn6aXtQ84WY-7J3Tpr2_j6sX0ch9yucS