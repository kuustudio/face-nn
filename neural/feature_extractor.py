#!/usr/bin/env python
# -*- coding: utf-8 -*-
# @Author: penghuailiang
# @Date  : 2019/10/16

import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
import logging
import util.logit as log
import utils
import os
from tqdm import tqdm

"""
feature extractor
photo生成engine face's params
input: photo solution: 512x512
output: engine params [95]
"""


class FeatureExtractor(nn.Module):
    def __init__(self, name, args, imitator, momentum=0.5):
        super(FeatureExtractor, self).__init__()
        log.info("construct feature_extractor %s", name)
        self.name = name
        self.imitator = imitator
        self.initial_step = 0
        self.args = args
        self.model_path = "./output/imitator"
        self.model = nn.Sequential(
            self.layer(3, 3, kernel_size=7, stride=2, pad=3),  # 1. (batch, 3, 256, 256)
            nn.MaxPool2d(kernel_size=3, stride=2, padding=1),  # 2. (batch, 3, 128, 128)
            self.layer(3, 8, kernel_size=3, stride=2, pad=1),  # 3. (batch, 8, 64, 64)
            self.layer(8, 16, kernel_size=3, stride=2, pad=1),  # 4. (batch, 16, 32, 32)
            self.layer(16, 32, kernel_size=3, stride=2, pad=1),  # 5. (batch, 32, 16, 16)
            self.layer(32, 64, kernel_size=3, stride=2, pad=1),  # 6. (batch, 64, 8, 8)
            self.layer(64, 95, kernel_size=7, stride=2),  # 7. (batch, 95, 1, 1)
        )
        self.optimizer = optim.SGD(self.parameters(),
                                   lr=args.extractor_learning_rate,
                                   momentum=momentum)

    @staticmethod
    def layer(in_chanel, out_chanel, kernel_size, stride, pad=0):
        return nn.Sequential(
            nn.Conv2d(in_chanel, out_chanel, kernel_size=kernel_size, stride=stride, padding=pad),
            nn.BatchNorm2d(out_chanel),
            nn.ReLU()
        )

    def forward(self, x):
        batch = x.size(0)
        log.info("feature_extractor forward with batch: %d", batch)
        return self.model(x)

    def itr_train(self, image):
        """
        这里train的方式使用的是imitator
        第二种方法是 通过net把params发生引擎生成image
        :param image: [batch, 3, 512, 512]
        :return: loss scalar
        """
        self.optimizer.zero_grad()
        param_ = self.forward(image)
        img_ = self.imitator.forward(param_)
        loss = utils.content_loss(image, img_)
        loss.backward()
        self.optimizer.step()

    def batch_train(self):
        log.info("feature extractor train")
        initial_step = self.initial_step
        total_steps = self.args.total_extractor_steps
        progress = tqdm(range(initial_step, total_steps + 1), initial=initial_step, total=total_steps)
        for step in progress:
            log.info("current step: ", step)
            if (step + 1) % self.args.extractor_save_freq == 0:
                state = {'net': self.model.state_dict(), 'optimizer': self.optimizer.state_dict(), 'epoch': step}
                torch.save(state, '{1}/model_imitator_{0}.pth'.format(step + 1, self.model_path))

    def load_checkpoint(self, path):
        """
        从checkpoint 中恢复net
        :param path: checkpoint's path
        """
        self.clean()
        checkpoint = torch.load(path)
        self.model.load_state_dict(checkpoint['net'])
        self.optimizer.load_state_dict(checkpoint['optimizer'])
        self.initial_step = checkpoint['epoch']
        log.info("recovery imitator from %s", path)

    def clean(self):
        try:
            if os.path.exists(self.model_path):
                os.remove(self.model_path)
            os.mkdir(self.model_path)
        except IOError:
            log.error("io error, path: ", self.prev_path, self.model_path)


if __name__ == '__main__':
    log.init("FaceNeural", logging.DEBUG, log_path="output/log.txt")
    extractor = FeatureExtractor("neural_extractor")
    y = extractor.forward(torch.randn(2, 3, 512, 512))
    log.info(y.size())