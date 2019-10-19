#!/usr/bin/env python
# -*- coding: utf-8 -*-
# @Author: penghuailiang
# @Date  : 2019-10-04

import numpy as np
import torch
import os
import cv2
import random
import struct
import util.logit as log
from util.exception import NeuralException


class FaceDataset:
    """
    由Unity引擎生成的dataset
    """

    def __init__(self, args, mode="train"):
        """
        Dataset construction
        :param args: argparse options
        :param mode: "train": 训练级； "test": 测试集
        """
        self.names = []
        self.params = []
        if mode == "train":
            self.path = args.path_to_dataset
        elif mode == "test":
            self.path = args.path_to_dataset
        else:
            raise NeuralException("not such mode for dataset")
        cnt = args.db_item_cnt
        self.args = args
        if os.path.exists(self.path):
            name = "db_description"
            path = os.path.join(self.path, name)
            log.info(path)
            f = open(path, "rb")
            for it in range(cnt):
                kk = f.read(10)[1:]  # 第一个是c#字符串的长度
                self.names.append(str(kk, encoding='utf-8'))
                v = []
                for i in range(args.params_cnt):
                    v.append(struct.unpack("f", f.read(4))[0])
                self.params.append(v)
            f.close()
        else:
            log.info("can't be found path %s. Skip it.", self.path)

    def get_batch(self, batch_size):
        """
        以<name, params, image>的形式返回
        formatter: [batch, ?]
        """
        names = []
        cnt = self.args.db_item_cnt
        params = torch.rand([batch_size, self.args.params_cnt])
        images = torch.rand([batch_size, 3, 512, 512])
        for i in range(batch_size):
            ind = random.randint(0, cnt - 1)
            name = self.names[ind]
            val = self.params[ind]
            name = name + ".jpg"
            path = os.path.join(self.path, name)
            image = cv2.imread(path)
            names.append(name)
            params[i] = torch.Tensor(val)
            image = np.swapaxes(image, 1, 0)
            image = np.swapaxes(image, 0, 2)
            image = image / 255.0
            images[i] = torch.Tensor(image)
        return names, params, images
