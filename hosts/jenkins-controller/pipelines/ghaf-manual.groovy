#!/usr/bin/env groovy

import groovy.transform.Field
@Field def MODULES = [:]

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def WORKDIR  = 'checkout'
def PIPELINE = [:]

properties([
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL),
  parameters([
    string(name: 'GITREF', defaultValue: 'main', description: 'Ghaf git reference (Commit/Branch/Tag)'),
    booleanParam(name: 'doc', defaultValue: false, description: 'Build target packages.x86_64-linux.doc'),
    booleanParam(name: 'lenovo_x1_carbon_gen11_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.lenovo-x1-carbon-gen11-debug'),
    booleanParam(name: 'lenovo_x1_carbon_gen11_debug_installer', defaultValue: false, description: 'Build target packages.x86_64-linux.lenovo-x1-carbon-gen11-debug-installer'),
    booleanParam(name: 'dell_latitude_7230_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.dell-latitude-7230-debug'),
    booleanParam(name: 'dell_latitude_7330_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.dell-latitude-7330-debug'),
    booleanParam(name: 'nvidia_jetson_orin_agx_debug_from_x86_64', defaultValue: false, description: 'Build target packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64'),
    booleanParam(name: 'nvidia_jetson_orin_nx_debug_from_x86_64', defaultValue: false, description: 'Build target packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64'),
    booleanParam(name: 'nvidia_jetson_orin_agx_debug', defaultValue: false, description: 'Build target packages.aarch64-linux.nvidia-jetson-orin-agx-debug'),
    booleanParam(name: 'nvidia_jetson_orin_nx_debug', defaultValue: false, description: 'Build target packages.aarch64-linux.nvidia-jetson-orin-nx-debug'),
    booleanParam(name: 'system76_darp11_b_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.system76-darp11-b-debug'),
  ])
])
pipeline {
  agent { label 'built-in' }
  options {
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  stages {
    stage('Reload only') {
      when { expression { params && params.RELOAD_ONLY } }
      steps {
        script {
          currentBuild.result = 'ABORTED'
          currentBuild.displayName = "Reloaded pipeline"
          error('Reloading pipeline - aborting other stages')
        }
      }
    }
    stage('Checkout') {
      steps {
        dir(WORKDIR) {
          checkout scmGit(
            branches: [[name: params.GITREF]],
            extensions: [[$class: 'WipeWorkspace']],
            userRemoteConfigs: [[url: REPO_URL]]
          )
        }
      }
    }
    stage('Setup') {
      steps {
        dir(WORKDIR) {
          script {
            def TARGETS = []
            if (params.doc) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.doc" ])
            }
            if (params.lenovo_x1_carbon_gen11_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug" ])
            }
            if (params.lenovo_x1_carbon_gen11_debug_installer) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug-installer" ])
            }
            if (params.dell_latitude_7230_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.dell-latitude-7230-debug" ])
            }
            if (params.dell_latitude_7330_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.dell-latitude-7330-debug" ])
            }
            if (params.nvidia_jetson_orin_agx_debug_from_x86_64) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64" ])
            }
            if (params.nvidia_jetson_orin_nx_debug_from_x86_64) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64" ])
            }
            if (params.nvidia_jetson_orin_agx_debug) {
              TARGETS.push(
                [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug" ])
            }
            if (params.nvidia_jetson_orin_nx_debug) {
              TARGETS.push(
                [ target: "packages.aarch64-linux.nvidia-jetson-orin-nx-debug" ])
            }
            if (params.system76_darp11_b_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.system76-darp11-b-debug" ])
            }
            MODULES.utils = load "/etc/jenkins/pipelines/modules/utils.groovy"
            PIPELINE = MODULES.utils.create_pipeline(TARGETS)
          }
        }
      }
    }
    stage('Build') {
      steps {
        dir(WORKDIR) {
          script {
            parallel PIPELINE
          }
        }
      }
    }
  }
}
