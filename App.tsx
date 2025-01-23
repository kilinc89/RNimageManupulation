/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 */

import React, { useEffect } from 'react';
import {
  Image,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import DefaultImage from './assets/woman.jpg';
import { NativeModules } from 'react-native';

const { ImageManipulation } = NativeModules;



function App(): React.JSX.Element {

  const [imgUrl, setImgUrl] = React.useState('');
  const [lipstickImgUrl, setLipstickImgUrl] = React.useState('');

  async function testManipulateImage() {
    try {
      const DEFAULT_IMAGE = Image.resolveAssetSource(DefaultImage).uri;
      const result = await ImageManipulation.convertToGrayscale(DEFAULT_IMAGE);
      console.log('result', result); // "Manipulated Image URL: https://example.com/image.jpg"
      setImgUrl(result);
    } catch (error) {
      console.error(error);
    }
  }

  async function addLipstickToImage() {
    try {
      const DEFAULT_IMAGE = Image.resolveAssetSource(DefaultImage).uri;
      const hexColor = '#FF0000'; // Ruj rengi (kırmızı)
      const resultUrl = await ImageManipulation.addLipstick(DEFAULT_IMAGE, hexColor);
      setLipstickImgUrl(resultUrl);
      console.log('Lipstick Image URL:', resultUrl);
    } catch (error) {
      console.error('Error:', error);
    }
  }

  useEffect(() => {
    const DEFAULT_IMAGE = Image.resolveAssetSource(DefaultImage).uri;
    console.log(333, DEFAULT_IMAGE);
    testManipulateImage();

    addLipstickToImage();

  }, []);

  return (
    <SafeAreaView >

      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
      >

        <View>
          <Text style={styles.highlight}>Original</Text>
        </View>

        <Image
          source={DefaultImage}
          style={{ width: 200, height: 200 }}
        />

        <Text style={styles.highlight}>Edited Gray</Text>
        <Image
          source={{ uri: imgUrl }}
          style={{ width: 200, height: 200 }}
        />
        <Text style={styles.highlight}>Lipstick added</Text>
        <Image
          source={{ uri: lipstickImgUrl }}
          style={{ width: 200, height: 200 }}
        />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  sectionContainer: {
    marginTop: 32,
    paddingHorizontal: 24,
  },
  sectionTitle: {
    fontSize: 24,
    fontWeight: '600',
  },
  sectionDescription: {
    marginTop: 8,
    fontSize: 18,
    fontWeight: '400',
  },
  highlight: {
    fontWeight: '700',
  },
});

export default App;
