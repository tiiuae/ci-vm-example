#!/usr/bin/env groovy

pipeline {
  agent any
  stages {
    stage('Test sh') {
      steps {
        sh 'echo Testing'
        sh 'pwd'
      }
    }
  }
}